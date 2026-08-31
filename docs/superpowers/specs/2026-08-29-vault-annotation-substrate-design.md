# Vault Annotation Substrate — Design

**Date:** 2026-08-29
**Status:** Approved for planning
**Code lands in:** `/home/b08x/WorkspaceV3/sfl-engine`
**Companion specs:** [TUI Rework](2026-08-29-tui-rework-design.md) · [Media Ingest + Onboarding](2026-08-31-media-ingest-and-onboarding-design.md)

> **Amended 2026-08-31.** This spec's audio `Source` and `Ingest::SourceResolver` are
> superseded by the Media Ingest spec: transcription returns typed segments from a
> local whisper.cpp backend, and path-to-loader dispatch extends the existing
> `Ingest::DeterministicRules` rather than adding a parallel resolver. Everything
> else here — pairing, rules annotation, provenance, correlation, dataset export —
> stands.

---

## Shape

One substrate, two thin consumers. The substrate is the product; the consumers are
small because it does the work.

```
        attachment + parent note
                 │
                 ▼
    pair → extract → Pass 1 (spaCy, local)
                 │
                 ▼
    annotate:  rules (default, local)  │  LLM (opt-in, curated subset)
                 │
                 ▼
    clauses + ideational + interpersonal + PROVENANCE
                 │
        ┌────────┴────────┐
        ▼                 ▼
   correlation       dataset export
   (local: NLI,      (JSONL by
    BERTopic)         provenance tier)
```

**Runs fully local by default.** No API key is required for any default path. An LLM
is opt-in, applied to a curated subset, and its role is *dataset production* — not a
runtime dependency.

## Problem

The vault at `/home/b08x/Notebook` holds 2,113 markdown notes and ~700 attachments
(227 PDFs, ~300 images, ~160 audio files, plus video, CSV, `.canvas`). Content enters
and is never compared against what is already there.

Two things follow from annotating it properly:

- **Correlation** — where an attachment's claims collide with, or are missing from,
  what was already captured.
- **Datasets** — SFL-annotated clause corpora for fine-tuning models.

## Non-goals

- **Agent chat / RAG Q&A over the vault.** Deliberately deferred, not rejected — a
  natural fit for a separate plugin later, built on this substrate's retrieval layer.
  It is the single largest source of scope creep here and is out.
- Automatic rewriting or merging of notes. The system proposes; the human decides.
- Vision descriptions of images. A 15-word visual description rarely contains an
  assertion that can contradict anything, and it is LLM-only. Images are extracted via
  kreuzberg OCR when they carry text, or skipped.
- Reconciling the 263 legacy `.meta.yaml` sidecars. Three incompatible ontologies (see
  the `RubyRAG_Notebook` repo's `AGENTS.md`); unrelated prior art, not input.
- Replacing `Analysis::TopicModeler` (tomoto). Different job — within-document topic
  shift — spec-covered, and it stays.

---

## Why this is slices of `sfl-engine`, not a new application

`sfl-engine` is at Phase 5 of 6 — 655 specs passing, RuboCop clean — and already
supplies most of the substrate:

| Need | Already exists |
|---|---|
| Claim-level storage | `clauses` (keyed on `external_id`, GIN tsvector on `text`) |
| Fact vs. stance split | `ideational_payloads` / `interpersonal_payloads` |
| **Local-only annotation** | **`--pass1-only`** — real CLI mode, *"Skip LLM annotation"*; `Pipeline#compile(pass_one_only:)` short-circuits to `stub_annotate_all` |
| Provenance | `AnnotationSource` enum + `TRUSTED_ANNOTATION_SOURCES` |
| Hybrid retrieval | `PgHybridRetriever` behind `Ports::Retriever` |
| Human triage | `review_queue` — already carries `modality: image\|text\|audio` + `source_file` — and `PgReviewQueueRepository` |
| PDF / markdown / canvas / CSV / image loaders | `kreuzberg`, `inkmark`, `json_canvas`, `csv` |
| Test seams | `Core::Ports` with `fake/` and `null/` throughout |

The `review_queue` schema was written for multi-modal attachment ingestion before this
project existed.

**Phase 7 discipline.** `sfl-engine` plans to split into `sfl-core`/`sfl-store`/
`sfl-llm`/`sfl-cli`. New slices live in their own namespaces and depend on existing
code *only through `Core::Ports`*, so they lift out as `sfl-ingest` and `sfl-correlate`
without rework.

### What genuinely does not exist

Attachment↔note pairing · an audio `Source` · a path→`Source` resolver · a rules-based
interpersonal annotator · contradiction detection (`Analysis::CorrelationAnalyzer` is
**not** this — it correlates `process_type` against tenor within turns) · cross-corpus
concept clustering · clause-level dataset export · batch orchestration with resume.

---

## Substrate

### 1. `Ingest::Pairing`

Binds each attachment to its parent note. Non-trivial because the vault has only 77
wikilink embeds and 186 markdown embeds against ~700 attachments — most pairing is
*conventional*: `assets/2024-01-29 RAG System Architecture/image-970-2130.png` pairs
with `Daily/RAG System Architecture.md`.

Three strategies, first hit wins:

1. **Explicit embed** — `![[target]]` / `![](path)` in a note body. Exact.
2. **Sibling folder** — containing-directory name matched against note basenames with
   `amatch` Jaro-Winkler (already a dependency), above a configurable threshold.
3. **Unpaired** — `parent_note: nil`. Not an error; an orphan still yields claims.

Strategy and confidence are recorded and propagate into `Unit#metadata`, so a fuzzy
pairing is never indistinguishable from an exact one.

Filesystem only — no database, no model. Fully unit-testable against a fixture tree.

### 2. `Ingest::SourceResolver`

Maps a path to its `Loaders::Source`. A frozen extension→factory registry. Unknown
extensions return `nil` and the file is skipped with a logged reason — never raised,
so one odd file cannot abort a 700-file batch.

### 3. `Ingest::AudioSource`

The one missing loader. Implements the existing duck:

```ruby
module SFL::Core::Loaders::Source
  def each_unit  # yields SFL::Core::Types::Unit
end
```

Wraps `whispercpp` — **local model, not an API** — harvested from
`/home/b08x/WorkspaceV3/RubyRAG_Ref/transcription-pipeline` (a working gem with a Thor
CLI and batch/error-handling examples). Transcription goes through an injected port so
specs never invoke Whisper.

Each segment becomes one `Unit` with `sent_at` from the segment timestamp, so
provenance reaches a point in the recording, not just the file.

**Degradation follows `ImageSource`'s precedent exactly:** on failure still emit a
`Unit` with filename and duration plus a truthful `transcription_failed` flag, and
enqueue to `review_queue` with `modality: "audio"`. Visible, never silently dropped.

### 4. `Annotation::RulesAnnotator` — the default path

Pass 1 (spaCy) is already fully local and yields the **ideational** payload —
`process_type`, `participants`, `circumstances`: *what was asserted*. That is the half
correlation compares.

Pass 2 (LLM) yields the **interpersonal** payload. Skipping it entirely sets
`annotation_source: "stub"` and leaves `modality_weight`/`tenor` at their `0.5`
defaults — which is a midpoint *by construction, not a measurement*.

The rules annotator recovers the two interpersonal fields the correlation gate
actually needs, deterministically, from data Pass 1 already persists. `SyntacticToken`
carries `lemma`, `pos`, `tag`, `dep`, `head_index` and spaCy's `morphology`:

- **`mood`** — declarative / interrogative / imperative, from the parse (auxiliary
  inversion, root verb form, terminal punctuation).
- **`modality_weight`** — a lexicon over lemmas and dependencies: modal auxiliaries
  (`might`, `could`, `must`, `will`), hedges (`seems`, `possibly`, `appears`), boosters
  (`clearly`, `definitely`, `always`).

**`tenor` and `speaker_attitude` are not deterministically tractable and are left
`nil`, not guessed.** A fabricated value is worse than an absent one — that is the
lesson `CorrelationAnalyzer` already encodes.

**Requires a new `"rules"` value in the `AnnotationSource` enum**
(`"llm"`, `"fallback"`, `"stub"`, `"chunk_artifact"`, `"human"`).

### 5. Provenance — load-bearing for both consumers

`annotation_source` is the quality tier, not bookkeeping:

| Source | Correlation | Dataset |
|---|---|---|
| `human` | authoritative | platinum — eval set |
| `llm` | trusted | gold — training set |
| `rules` *(new)* | trusted for mood/modality only | silver — baseline, and the thing being measured against |
| `fallback` · `stub` · `chunk_artifact` | **excluded** | **excluded** |

`TRUSTED_ANNOTATION_SOURCES` already exists as this filter. It keeps compiler-substituted
`0.5` midpoints out of contradiction adjudication *and* out of training data — the same
guard serving both consumers.

**Open decision:** whether `"rules"` joins `TRUSTED_ANNOTATION_SOURCES` wholesale or a
narrower per-field predicate is introduced, since rules are trustworthy for
mood/modality but supply nothing for tenor. Recommend the narrower predicate;
widening the existing constant would silently assert tenor trust that does not exist.

### 6. Orchestration — `Nexo::Workflow`

> **Correction to `gems.json`:** its `nexo` entry describes "Integrate a Rails app with
> external services" with `rails`/`googleauth`/`kaminari` deps, classified
> `primary: "ai_nlp"` at confidence 1.0 — internally contradictory, and describing a
> different gem sharing the name. The real `maquina-app/nexo` is an agent harness for
> the RubyLLM ecosystem (Ruby ≥ 3.3, `ruby_llm`). `gems.json` should be corrected.

**Adopted — orchestration only:**

- `Nexo.concurrent(max_in_flight: N)` — bounded fan-out, ordered results, first error
  propagated. Replaces the `sleep 5` + single-retry loop in `scripts/process_assets.rb`.
- `Workflow#checkpoint_all` — persistence-aware fan-out; an interrupted batch re-runs
  only incomplete tasks. The principled form of the legacy "skip if `.meta.yaml`
  exists" hack, and it matters across ~700 attachments.
- `suspend!` / `resume` — suspend awaiting human triage, persist, resume in another
  process without re-paying for extraction.
- `Nexo::RunStore::Disk` — durable runs as one atomic JSON doc per run. No database,
  no Rails. Single-process, which suits a CLI.

**Rejected:** `Nexo::Agent`, skills, sandboxes, permissions. That layer wraps
`ruby_llm`; `sfl-engine` is a **DSPy** application with its own `signatures/`,
`annotators/`, `lm_factory`, `degradation`, `derivation_hash` and OpenTelemetry.
Two LLM stacks for no gain.

**Accepted cost:** `ruby_llm` enters the dependency tree unused. A precedent briefly
existed — `tui-implementation-plan.md` §2.4 adopted `ruby_llm-mcp` for the trackboi
board — but the [TUI Rework](2026-08-29-tui-rework-design.md) drops that pane and its
dependency. Nexo is now the *sole* reason `ruby_llm` appears. The argument stands on
its own (orchestration primitives are not an LLM stack; DSPy calls sit inside
`checkpoint` blocks) but it stands alone.

---

## Consumer A — Correlation *(fully local)*

### Contradictions

**Candidates** come from the existing `Ports::Retriever`
(`retrieve(RetrievalQuery) -> Array<RetrievalResult>`), already blending pgvector
semantic search with keyword search. Only retrieved *pairs* reach the model; the
corpus is never compared pairwise.

**Adjudication** is a local cross-encoder NLI model via `informers` (ONNX) — free,
offline, deterministic, unlimited to re-run.

**NLI runs over the ideational payload, not raw clause text.** Comparing
`process_type` + `participants` + `circumstances` compares what was asserted, stripped
of the rhetoric around it. This is why SFL annotation sits upstream of correlation.

**Two gating rules, both load-bearing:**

1. **Modality gate.** A hedged claim (*"this might cause latency"*) and an assertive
   one (*"this causes latency"*) are two positions on one question, not a
   contradiction. Both sides must clear a modality floor.
2. **Trusted-source filter.** Only clauses whose `annotation_source` is trusted are
   adjudicated. A `stub`/`fallback` clause sits at `0.5` by construction; treating that
   as medium confidence would adjudicate on a fabricated number.

**Output:** a `contradictions` table — `clause_a_id`, `clause_b_id` (FKs to
`clauses.external_id`, `on_delete: cascade`, matching the payload tables' D5
convention), `verdict`, `nli_score`, `modality_delta`, `status`, `detected_at`. Unique
index on the ordered pair keeps re-runs idempotent.

`verdict` is one of:

- `contradiction` — NLI fired **and** both clauses clear the modality floor
- `tension` — NLI fired but at least one clause is hedged below the floor
- `unadjudicated` — at least one clause has an untrusted `annotation_source`

Only `contradiction` is enqueued for review by default; all three are stored and
queryable, so a miscalibrated floor is re-swept without re-running extraction or NLI.
Because the whole path is local, re-sweeping is free.

Confirmed rows enqueue via
`PgReviewQueueRepository#enqueue(document_id:, modality:, source_file:,
generated_text:, reason:, source_type:, content_type:)`.

### Gaps

**BERTopic over the clause store**, chosen over the incumbent tomoto for two
non-cosmetic reasons:

1. **LDA degrades on short documents**, and the units here are clauses — close to its
   worst case.
2. **LDA cannot express a gap.** It assigns every document a topic distribution.
   BERTopic's HDBSCAN stage produces genuine outliers (`-1`) and small low-density
   clusters — exactly "this recurs across sources but was never consolidated."

**The seams already exist.** `Analysis::Engine` injects the modeller as
`topic_modeler_factory: -> (k:) { TopicModeler.new(k:) }`, and specs already substitute
a double — a second modeller is a constructor argument, not a refactor. And
`sidecar/spacy_sidecar.py` already establishes the Python bridge, so BERTopic being
Python-only adds no new architecture.

**Embeddings are precomputed** — already in pgvector via `Ports::Embedder`. The sidecar
runs only UMAP → HDBSCAN → c-TF-IDF. No `sentence-transformers`, no recompute. *Verify
the precomputed-embeddings kwarg against the installed BERTopic version rather than
assuming it.*

**Hazard — topic identity drift.** UMAP is stochastic; topic *indices* are not stable
across runs even when seeded. Persisted topics are keyed by representative terms and
centroid, never index. Storing a raw topic number is wrong.

## Consumer B — Dataset export

No clause-level export exists today; the `Formatters` are all report-level summaries,
and `jsonl` appears only in loaders that *read* exports.

A `BaseFormatter` subclass emitting one JSON object per clause — text, document and
source provenance, ideational payload, interpersonal payload, `annotation_source`, and
`reasoning_trace` where present — as JSONL. `jsonl` is already in `gems.json`.

**Filtered by provenance tier**, so a training export cannot silently include
compiler-substituted defaults. Tier selection is explicit at the call site; there is no
"everything" default.

This is the only consumer that justifies the LLM path: run Pass 2 over a curated
subset to produce gold annotations, correct them through Triage (`llm` → `human`),
export, fine-tune, then deploy the tuned model through `informers` so the *local* path
gains high-quality interpersonal annotation for free. The LLM works itself out of the job.

---

## Error handling

Follows conventions already in this codebase.

- **Extraction failure** — emit a `Unit` with a truthful flag
  (`transcription_failed`), enqueue to `review_queue`. Never drop silently.
  Precedent: `ImageSource`.
- **Unknown file type** — skip with a logged reason; never raise.
- **Untrusted annotation** — excluded from adjudication and from export; surfaced as
  `unadjudicated`. Precedent: `CorrelationAnalyzer`'s `annotated_count` vs `count`.
- **Sidecar unavailable** — the affected stage degrades and the run reports partial
  results. Contradiction detection does not depend on BERTopic.
- **LLM path only** — existing `LLM::Degradation` applies unchanged. No default path
  can fail this way, because no default path calls a provider.

## Testing

- **Pairing** — fixture tree covering all three strategies plus the ambiguous case
  where two notes match one folder within threshold.
- **AudioSource** — injected transcriber port; the failure path (flag + enqueue) is as
  important as the success path.
- **RulesAnnotator** — table-driven over hand-built token sequences: each modal, hedge
  and booster, and the three moods. Assert `tenor` stays `nil`.
- **Contradiction** — two cases carry the design: (a) hedged vs. assertive phrasing of
  one claim must **not** be a contradiction; (b) a `stub` clause must **not** be
  adjudicated on its default `0.5`.
- **Gaps** — faked sidecar; assert stable topic identity across two runs with shuffled
  input (the UMAP drift regression).
- **Export** — assert untrusted tiers cannot appear in a training export.
- **Workflow** — assert `checkpoint_all` does not re-run completed steps after a
  simulated interruption.

New ports (transcriber, NLI adjudicator, topic backend) each get `fake/` and `null/`
implementations, matching the existing `Core::Ports` layout.

## Build order

1. `Ingest::Pairing` + `SourceResolver` — filesystem only. Verifiable against the real
   vault immediately: does it pair ~700 attachments correctly?
2. `Ingest::AudioSource` — completes format coverage.
3. `Annotation::RulesAnnotator` + the `"rules"` provenance value.
4. Workflow wrapper over extraction + annotation. **The store is now populated and the
   system is useful**, before any consumer exists.
5. `contradictions` table + contradiction detection. First findings.
6. Dataset export formatter. Small, and independent of 5.
7. Gap clustering + BERTopic sidecar. Last: depends on a populated store and adds the
   only new external runtime.

## Open questions for implementation

- NLI model choice and its ONNX availability through `informers`.
- Whether `"rules"` joins `TRUSTED_ANNOTATION_SOURCES` or gets a per-field predicate
  (recommend the latter).
- Modality floor separating `contradiction` from `tension` — calibrate against real
  vault data, not a guessed constant. Cheap to iterate because the path is local.
- Jaro-Winkler threshold for folder pairing — likewise calibrated.
- Whether `whispercpp` is vendored from `transcription-pipeline` or depended on directly.
