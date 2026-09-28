` tags.

---

<blog>

# Golden Master Testing

Golden Master (characterization) testing pins a **stable baseline of system output** so that future refactors can be diffed against it. This page documents the golden-master fixture structure, the two fixture sets committed under `spec/fixtures/golden_master/`, the RSpec spec that drives the diff, and the precise failure semantics that make this a regression gate rather than a mere assertion on a single run.

## The two fixture sets are not interchangeable

The fixture catalog is deliberately asymmetric, and the asymmetry is a feature — it encodes a documented decision about which outputs are deterministic enough to pin.

| Fixture set | Subcommand | Determinism | Regression gate? | Rationale |
|---|---|---|---|---|
| `conversation/` | `sfl-analyze conversation` | **Byte-stable** | **Yes** | `--pass1-only` correctly suppresses Pass 2; every clause is stubbed; no LLM/network calls |
| `documentation/` | `sfl-analyze documentation` | **Not reproducible** | **No** | `--pass1-only` did **not** suppress Pass 2 (6/6 clauses annotated via real API calls); LLM non-determinism and `analyzed_at` timestamps break byte-reproducibility |

Sources: `spec/fixtures/golden_master/README.md`

The `README.md` is the authoritative note on this division. The `conversation/` fixture is the canonical gate; `documentation/` is kept only as a reference for actual historical behavior and must not be treated as a byte-exact baseline.

Sources: `spec/fixtures/golden_master/README.md`

## The "stub" contract: why `annotation_source` is a first-class value

The golden-master pattern only works because **Pass 2's absence is itself a labeled, observable output**. In `--pass1-only` mode the pipeline must not merely skip annotation; it must record that the clause is un-reviewed with an explicit `annotation_source: "stub"` so downstream consumers (and diff readers) can tell a stub from a real `llm` annotation.

This is enforced at three levels and is the same single source of truth that the refactored `Pipeline` uses:

- **`SFL::Core::Types::TRUSTED_ANNOTATION_SOURCES`** = `%w[llm human]` — the centralized list of annotation sources whose values are trusted for grounding, quality scoring, and "needs attention" predicates. Everything else (`stub`, `fallback`, `chunk_artifact`) is compiler-substituted.
- **`Core::Ports::Null::Annotator`** — the stub annotator. `annotate_batch` returns `AnnotationResult` objects with `mood: "declarative"`, `modality_weight: 0.5`, `tenor: 0.5`, `annotation_source: "stub"`. This is one of the consumers that the pipeline's `pass_one_only: true` path routes through (`stub_annotate_all`).
- **`Analysis::Engine#report_progress`** uses `TRUSTED_ANNOTATION_SOURCES` to count `defaulted` clauses, so the progress event carries the same honesty about stubbed output.
- **`Pipeline#compile`** exposes `pass_one_only: false` as a parameter. When truthy it **returns early from Pass 2 entirely** via `stub_annotate_all`, routing through `Null::Annotator` rather than re-duplicating stub values in the pipeline file itself. The `pass_one_only` flag is described in `lib/sfl/core/pipeline.rb` as the "single, structural fix" for the documentation golden-master bug: legacy had two independently-maintained copies of "should I run Pass 2 or stub it" (one in `ConversationAnalyzer`, one in `DocumentationAnalyzer`), and the second one drifted.

Sources: `lib/sfl/core/types/trusted_annotation_sources.rb`, `lib/sfl/core/ports/null/annotator.rb`, `lib/sfl/analysis/engine.rb`, `lib/sfl/core/pipeline.rb`

## Fixture shape: how `conversation_analysis.json` is structured

The committed golden file is the **legacy CLI's `sfl-analyze conversation` report**, not a `Wire.dump` of `AnalysisResult` (which is an intentional, documented boundary). It therefore has a report-shaped envelope the spec does **not** diff wholesale:

- `metadata` — `conversation_id`, `source_file`, `turn_count`, `speakers`, `analyzed_at`, `topics_enabled`, `interrupted`, `total`, and `annotation_coverage` (with `total_clauses`, `llm`, `human`, `fallback`, `stub`, `defaulted_pct`).
- `turns[]` — one object per turn, each carrying the flat field set `spec/analysis/engine_conversation_golden_master_spec.rb` actually diffs: `turn_id`, `speaker`, `timestamp`, `preview`, `avg_tenor`, `avg_modality`, `dominant_mood`, `tenor_shift`, `clause_count`, `defaulted_count`, `dominant_topic`, `topic_distribution`, `semantic_coherence_score`, and a `clauses[]` array of `{id, annotation_source, reasoning_trace}`.
- Optional top-level report sections: `tenor_timeline`, `field_evolution`, `correlations`, `insights`, `topic_labels`, `topic_evolution`, `key_moments`, `speaker_profiles`.

The `conversation_analysis.csv` and `conversation_analysis.md` siblings are rendered equivalents of the same fixture (the CSV is the field-wise header used by `awk`-style consumers; the MD is the human-readable report the legacy CLI emitted).

Sources: `spec/fixtures/golden_master/conversation/conversation_analysis.json`, `spec/fixtures/golden_master/conversation/conversation_analysis.csv`, `spec/fixtures/golden_master/conversation/conversation_analysis.md`

## The diffing spec: what gets compared, and what is explicitly excluded

`spec/analysis/engine_conversation_golden_master_spec.rb` is the single characterization spec. It runs `Analysis::Engine` against `ConversationSource` with a **pass1-only stub** (no real spaCy sidecar, no real LLM), and diffs the resulting `Core::Types::AnalysisResult` against the fixture **field-by-field at the `AnalysisResult`-structural level** rather than doing a byte-exact CLI-JSON diff. That scope is intentional: the fixture is legacy `sfl-analyze` *report* output (previews, annotation coverage, per-clause ids) — a formatter this codebase has not built yet — so a byte-exact CLI diff isn't in scope for this slice.

The spec's four expectations form a regression proof:

1. **Never calls Pass 2** — `allow(pass_two).to receive(:annotate_batch)` and `expect(pass_two).not_to have_received(:annotate_batch)`. This proves `pass_one_only: true` flows through to `Pipeline#compile` and into `Pipeline#annotate` without invoking the annotator port.
2. **Turn count and speakers** — `result.turns.size == golden_master[:metadata][:turn_count]`; `result.turns.map(&:speaker).uniq == golden_master[:metadata][:speakers]`.
3. **Every per-turn stub-mode field** — `golden_master[:turns].each_with_index` drives a field-by-field comparison of `turn_id`, `speaker`, `timestamp.iso8601`, `avg_tenor`, `avg_modality`, `dominant_mood`, `tenor_shift`, `clause_count`, `dominant_topic`, `semantic_coherence_score`. The comment is explicit: itemized expectations pinpoint *which* field regressed instead of collapsing to an opaque `Hash#==` failure.
4. **Stub clause values** — `turn.clauses.flat_map(&:clauses).each` asserts `mood == "declarative"`, `modality_weight == 0.5`, `tenor == 0.5`, `annotation_source == "stub"`, `textual.topical_theme == nil`.

The most important exclusion is named in the spec comment: `metadata.analyzed_at` (and any other wall-clock timestamp) is **never** stable across runs and is excluded. Likewise, `regression: true` holds for anything outside `conversation/` — re-running that fixture will not reproduce identical output because of LLM non-determinism.

Sources: `spec/analysis/engine_conversation_golden_master_spec.rb`

## The architectural consequence: `pass_one_only` is now a single source of truth

Before the refactor, the decision "run Pass 2 or stub it" lived in two duplicated code paths that drifted. The current architecture resolves this by pushing the decision to **`Pipeline#compile`** itself, which is the composition point for "compile a document" (not the whole app's composition root — that is still `Boot`, Phase 4). The implications:

- **No more per-subcommand divergence.** `ConversationSource` and `DocumentationSource` both forward `pass_one_only:` through `Engine#analyze`, which forwards it to `Pipeline#compile`. There is exactly one implementation that every future caller inherits.
- **`stub_annotate_all` is the reusable stub.** `Pipeline` uses `Ports::Null::Annotator` rather than re-literalizing the stub `InterpersonalPayload`/`TextualPayload` values. The same "what does a stub look like" definition is shared by `pass_one_only: true` and by any test that DI's `Null::Annotator` directly as `pass_two`.
- **Cache self-healing is annotation-source aware.** `Pipeline#annotate_with_cache` partitions cache keys, then filters hits through `TRUSTED_ANNOTATION_SOURCES`, treating untrusted (`stub`/`fallback`/`chunk_artifact`) cache entries as misses. This means a poisoned/corrupted cache (where a stub was written but the `TRUSTED` predicate missed it) cannot silently poison a re-run.

Sources: `lib/sfl/core/pipeline.rb`, `lib/sfl/analysis/engine.rb`, `spec/analysis/engine_conversation_golden_master_spec.rb`

## Why `conversation/` is byte-stable and `documentation/` is not

This is the cheapest way to reason about golden-master scope:

- **Deterministic path (`conversation/`):** `--pass1-only` suppresses Pass 2; `annotation_coverage.llm == 0`; all 8 clauses are `DEFAULTED`/`stubbed`. No LLM calls, no cost, no non-determinism. The fixture was captured 2026-07-24 by running the legacy repo's CLI against `spec/fixtures/inputs/`.
- **Non-deterministic path (`documentation/`):** `--pass1-only` did **not** suppress Pass 2 for the documentation subcommand. The output shows `annotation_coverage.llm == 6` (6/6 clauses really annotated, real API calls, real cost). Re-running it will not reproduce identical output (LLM non-determinism), and `analyzed_at` timestamps differ on every run. It is kept as a reference for actual system behavior, not as a regression gate, until the `--pass1-only` gap for the documentation subcommand is understood and the fixture regenerated in stub mode.

The intended maintenance rule, from the README: **exclude `metadata.analyzed_at` (and any other wall-clock timestamp); treat any other diff in `conversation/` as a regression.** Expect no other diffs in `conversation/` modulo the F4 rounding fix.

Sources: `spec/fixtures/golden_master/README.md`, `spec/analysis/engine_conversation_golden_master_spec.rb`

## How the diff is run (and how to add a new golden-master scenario)

Because `ConversationSource` reuses the `Core::Loaders::Source` duck (`each_unit` / `units` contract), the same `Analysis::Engine` application service serves the conversation path and would serve any future source (KnowledgeBaseSource is listed as a later slice). To add a new golden-master scenario:

1. Capture the legacy CLI output into `spec/fixtures/golden_master/<category>/` as `<category>_analysis.json` (plus CSV/MD renderings if useful).
2. Update the corresponding spec to load the fixture and diff the structural fields the engine actually produces. Follow the field-by-field pattern in `engine_conversation_golden_master_spec.rb` (either a full object structural comparison, or the `each_with_index` field iteration).
3. If the new scenario's output is deterministic (like `conversation/`), it becomes a regression gate. If it depends on an LLM (like `documentation/`), it is a **reference fixture, not a gate**, and `analyzed_at` and other timestamps must be excluded.

The existing spec naming convention (`engine_conversation_golden_master_spec.rb`) and fixture layout (`conversation/`, `documentation/`) are the pattern to extend.

Sources: `spec/analysis/engine_conversation_golden_master_spec.rb`, `spec/fixtures/golden_master/README.md`, `lib/sfl/analysis/conversation_source.rb`, `lib/sfl/analysis/documentation_source.rb`

## Provenance and phase markers

The fixture set is labeled `Phase 0` — captured fixtures with the legacy repo's CLI in hand, used as the characterization baseline for the rebuild. The `README.md` at `spec/fixtures/golden_master/` is the authoritative provenance note for this directory; it is intended to be read before any golden-master fixture is regenerated or deleted.