# Intelligent Ingest Layer — Design

**Date:** 2026-08-06
**Status:** Approved (design phase) — not yet implemented

## Problem

Ingest dispatch today is entirely deterministic and split across two unrelated files:
`Analysis::ChatExportExpander.detect_format`/`.loader_for` (`lib/sfl/analysis/chat_export_expander.rb:37-78`,
JSON-key sniffing for ChatGPT/Claude exports) and `Analysis::KnowledgeBaseSource#loader_for`
(`lib/sfl/analysis/knowledge_base_source.rb:178-185`, file-extension matching for
`.md`/`.canvas`/`.pdf`/images). Both are correct for the shapes they already know about, but:

- Any input format without an existing loader (e.g. a JSONL export from an unsupported tool,
  an HTML chat export) fails hard with no path to recognition.
- The same file extension (e.g. `.md`) can be a chat transcript or documentation, and nothing
  today distinguishes those cases by content.
- The CLI requires the user to already know which subcommand (`conversation` /
  `knowledge-base` / `documentation`) applies before pointing it at a file.
- There's no UI yet, so any review/approval step has to work as a file-based, CLI-driven
  workflow — not a queue a human browses in a browser.

## Goals

- One CLI entry point (`sfl-analyze ingest <path>`) that classifies and dispatches a file or
  a directory of mixed file types without the user pre-selecting a mode.
- Handle genuinely new formats by drafting a candidate loader for human review, rather than
  failing or attempting silent LLM-only extraction indefinitely.
- Route low-confidence classifications to a reviewable record instead of guessing.
- Reuse this codebase's existing per-task model-selection convention
  (`SFL_TASK_<NAME>_{MODEL,PROVIDER,TEMPERATURE}`, `lib/sfl/boot.rb:229`) rather than inventing
  a new "model tier" architecture — classification and loader-drafting are just two more task
  names.
- Leave `Core::Pipeline`, `Analysis::Engine`, and the three existing `Analysis::*Source`
  classes (`ConversationSource`, `KnowledgeBaseSource`, `DocumentationSource`) completely
  unchanged. This is a new layer above them, not a rewrite of them.

## Non-goals

- Redesigning Pass 2's interpersonal/textual annotation logic or its model selection — Pass 2
  already takes an injectable model/provider via `SFL_TASK_PASS_TWO_ANNOTATION_*`; this design
  only adds two new task names alongside it.
- A database-backed review queue (like `PgReviewQueueRepository`) or any UI for reviewing
  low-confidence classifications or drafted loaders — out of scope until a UI exists.
- Automatically registering or executing an LLM-drafted loader against real data. A drafted
  loader is always inert until a human reviews and wires it in.

## Architecture

```
sfl-analyze ingest <path>
        │
        ▼
Ingest::Orchestrator  ─── walks path (file or directory)
        │
        │  per file:
        ▼
Ingest::DeterministicRules.classify(file)
        │
   match? ──yes──▶ dispatch directly (existing Sources, unchanged)
        │
        no
        ▼
Core::Ports::Classifier#classify(sample)   [tier: ingest_classification, cheap]
        │
   confidence ≥ threshold? ──yes──▶ dispatch to (format, mode) it named
        │
        no
        ▼
   format recognized but ambiguous mode?
        │                          │
      yes                          no (format itself unrecognized)
        │                          │
        ▼                          ▼
  write to review manifest    Ingest::LoaderDrafter#draft(sample)  [tier: loader_drafting, reasoning]
  (skip this file, continue)  writes candidate lib/sfl/core/loaders/*_source.rb
                               + review doc, skips this file, continue

        ▼ (all files processed)
  End-of-run summary report: N dispatched, N flagged for review, N drafted-loader-pending
```

Dispatch targets are the three **existing, unchanged** engines: `Analysis::ConversationSource`,
`Analysis::KnowledgeBaseSource`, `Analysis::DocumentationSource` → `Analysis::Engine` /
`Core::Pipeline`. The Orchestrator only decides *which* of these to call and with *which
loader* — it doesn't reimplement any of them.

## Components

### `Ingest::DeterministicRules` (new module, unifies existing logic)

Pulls the extension-based checks currently in `knowledge_base_source.rb:178` and the JSON-key
sniff currently in `chat_export_expander.rb:37` into one place. Same behavior as today, just
de-duplicated — this is the free/instant fast path, unchanged for every file type already
supported today.

`#classify(path) → {format:, mode:, loader_class:} | nil` (nil = no deterministic match, fall
through to the LLM classifier)

### `Core::Ports::Classifier` (new port)

Follows the existing port convention (`Core::Ports::Annotator`, `Core::Ports::Embedder`):

```ruby
module SFL::Core::Ports
  module Classifier
    def classify(sample)  # @return Core::Types::ClassificationResult
    end
  end
end
```

Adapters: `LLM::Classifier` (real, `RubyLLM::Schema`-constrained, following the same pattern as
`LLM::Schemas::ClauseAnnotationSchema`), plus `Null::Classifier`/`Fake::Classifier` for tests —
matching every other port in this codebase.

### `Core::Types::ClassificationResult` (new `Dry::Struct`)

- `format:` (Symbol, e.g. `:chatgpt_export`, `:markdown_chat`, `:unknown`)
- `mode:` (`:conversation` / `:knowledge_base` / `:documentation`, nilable)
- `confidence:` (Float, 0.0–1.0)
- `reasoning:` (String)

Mirrors the existing `Core::Types::ReasoningTrace` pattern from Pass 2 so classification
decisions are auditable the same way annotation decisions already are.

### `Ingest::LoaderDrafter` (new, reasoning-tier)

`#draft(sample, path) → {loader_path:, doc_path:}`. Writes a candidate
`lib/sfl/core/loaders/<name>_source.rb` implementing the `Core::Loaders::Source` mixin contract
(`#each_unit`), plus a markdown review doc: sample input, proposed field mapping, confidence,
and why existing loaders didn't match.

**Safety boundary:** does not register or load the drafted file automatically. It is inert
until a human reviews it and wires it in (adds the `require` and a `DeterministicRules` table
entry). No code path exists for a drafted loader to execute against real data unreviewed.

### `Ingest::ReviewManifest` (new, file-based — not a DB table)

A single JSON/YAML file per ingest run (e.g. `.sfl-ingest-review/<timestamp>.yml`) listing every
low-confidence or drafted-loader file with the classifier's reasoning. File-based rather than a
`PgReviewQueueRepository`-style DB table because there's no UI yet to browse a DB table — a file
you can read and act on is the right weight here. The manifest is advisory, not a blocking DB
state: resolving an entry (deleting it, or fixing/registering the loader) and re-running
`ingest` picks up cleanly without reprocessing already-dispatched files.

### `Ingest::Orchestrator` (new, the coordinator)

Walks the given path (file or directory), runs the flow above per file, dispatches matches to
the existing three engines unchanged, accumulates the end-of-run summary report.

### Model tiering — two new task-config entries, zero new architecture

Following the existing `SFL_TASK_<NAME>_{MODEL,PROVIDER,TEMPERATURE}` convention
(`lib/sfl/boot.rb:229`, already used for `pass_two_annotation`/`embedding`):

- `SFL_TASK_INGEST_CLASSIFICATION_*` — small/cheap model (similar cost tier to embedding)
- `SFL_TASK_LOADER_DRAFTING_*` — a stronger reasoning model, since drafting a parser from a raw
  sample is a harder task than classification

Pass 2 annotation is unaffected — it keeps using `SFL_TASK_PASS_TWO_ANNOTATION_*` as it does
today.

## Data Flow — worked example

Input: `export-dump/weird_chat.jsonl` (a JSONL export from a tool with no existing loader)

1. `Orchestrator` hits the file, calls `DeterministicRules.classify` — extension `.jsonl` isn't
   in the extension table, and it's not the ChatGPT/Claude JSON shape (which expects a
   top-level JSON array/object with `mapping`/`chat_messages` keys, not JSONL) → **no match**.
2. Falls to `Core::Ports::Classifier#classify`, given a sample (first N lines/bytes, not the
   whole file — keeps the classification call cheap regardless of file size). Model tier:
   `ingest_classification`. Returns e.g. `{format: :unknown, mode: nil, confidence: 0.2,
   reasoning: "JSONL rows with 'role'/'content' keys resembling a chat log, but no loader
   recognizes this exact shape"}`.
3. Confidence below threshold **and** format is `:unknown` (not just an ambiguous-mode case) →
   routes to `LoaderDrafter`, not the review manifest directly.
4. `LoaderDrafter#draft` (tier: `loader_drafting`) reads a larger sample, drafts
   `lib/sfl/core/loaders/generic_jsonl_chat_source.rb` implementing
   `Core::Loaders::Source#each_unit`, plus `docs/ingest-review/generic_jsonl_chat_source.md`
   (sample rows shown, proposed `speaker`/`text`/`sent_at` field mapping, confidence,
   reasoning).
5. This file is recorded in the run's `ReviewManifest` as `status: loader_drafted`, and
   **skipped** — it does not get dispatched to any engine this run.
6. Orchestrator continues to the next file in the directory; a drafted-loader entry doesn't
   halt the whole batch (consistent with the existing **F11** partial-failure-isolation
   principle already in this codebase — one file's issue doesn't take the rest down).
7. End of run: summary printed (`12 dispatched, 1 loader drafted for review, 0 flagged
   low-confidence`), pointing at the manifest file.

**Contrast case — ambiguous mode, not unrecognized format:** a `.md` file the classifier reads
as `{format: :markdown, mode: :conversation, confidence: 0.4, reasoning: "Has speaker-labeled
lines but also prose paragraphs — could be a pasted chat log or documentation with dialogue
examples"}` → format *is* known (`:markdown`, a loader exists), only `mode` is uncertain → goes
straight to the `ReviewManifest` as `status: low_confidence_mode`, no `LoaderDrafter` involved,
since there's nothing to draft.

## Error Handling

Follows this codebase's existing conventions rather than inventing new ones:

- **Classifier LLM call fails/times out** (wrapped in `Core::Ports::Breaker`, same as
  `Embedder`/`Engine`): treated as confidence `0.0`, not a raised error — falls through to the
  low-confidence path (review manifest), never silently skips the file entirely. Logged at
  `WARN` via the injected `Core::Ports::Logger`, matching Pass 2's `log_classification_gap`
  pattern.
- **LoaderDrafter fails** (bad LLM response, schema violation): the file is recorded in the
  manifest as `status: draft_failed` with the error message — not a crash, not silently
  dropped.
- **One file's failure never aborts the batch** — same **F11** partial-failure-isolation
  principle already established in `cli.rb` for conversation-file batches; the Orchestrator's
  per-file step is wrapped the same way.
- **Deterministic-rules false confidence is not possible by construction** — that path only
  ever returns a match for the exact shapes it already checks today (unchanged behavior), so
  there's no new failure mode introduced there.
- **Drafted loaders are never auto-loaded** — a deliberate safety boundary, not just a workflow
  choice (see `LoaderDrafter` above).

## Testing

- `Ingest::DeterministicRules` — pure unit tests, table-driven; every existing extension/JSON-key
  case must still pass unchanged (this is a refactor-with-tests-first move, consolidating two
  existing, already-tested code paths).
- `Core::Ports::Classifier` — tested against `Fake::Classifier` everywhere except a small
  adapter-level spec for `LLM::Classifier` itself (same pattern as the existing embedder specs
  against a stubbed `ruby_llm`).
- `Ingest::LoaderDrafter` — spec asserts it writes both files with expected structure given a
  `Fake::Classifier`/stubbed LLM response; does not assert the drafted loader is syntactically
  valid Ruby by default (that's what human review is for), though a `ruby -c` sanity check on
  the drafted file before writing is cheap enough to include.
- `Ingest::Orchestrator` — the integration-level spec: a fixture directory with one of each case
  (deterministic match, low-confidence mode, unrecognized format) asserts the right
  dispatch/manifest-entry/draft outcome per file, and that a failure in one file doesn't stop
  processing the rest.
- `Ingest::ReviewManifest` — round-trip test (write entries, re-read, confirm shape) plus a
  rerun test: resolving an entry and re-running doesn't reprocess already-dispatched files.

## Open Questions for Implementation Planning

- Exact confidence threshold value(s) for "deterministic-equivalent" vs. "needs review" — start
  as a constant, tune later.
- Whether `LoaderDrafter`'s sample size needs to scale with file size (e.g. always read the
  first N records rather than N bytes for line-delimited formats).
- CLI flag surface for `sfl-analyze ingest` (e.g. `--dry-run` to classify without dispatching,
  `--manifest-dir` override).
