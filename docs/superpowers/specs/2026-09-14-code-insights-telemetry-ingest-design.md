# Code-insights telemetry ingest

Date: 2026-09-14
Status: approved design, not yet implemented
Author: brainstormed with Claude Opus 5

## Objective

Let sfl-engine ingest AI coding session telemetry from `~/.code-insights/data.db` as a first-class corpus: conversation turns in the `conversation` register, distilled insights in a new `analytic` register, and tool traffic in a new `tool_trace` register, all hanging off a shared session parent clause. Each insight carries a computed grounding score that says how defensible it is from the turns it claims to cite, and that score is explainable down to a specific sibling clause.

## Background

code-insights records AI coding sessions across eight harnesses and runs an LLM analysis pass that emits four kinds of insight: `decision`, `learning`, `summary`, `prompt_quality`. The decision rows are structured and unusually rich. Every one carries `situation`, `choice`, `reasoning`, and `alternatives`; 8,181 of 8,186 also carry `revisit_when`, a machine-readable condition under which the decision should be reopened.

That corpus is currently only queryable by SQL and by a vector index that is easy to misuse. Putting it through sfl-engine gives it SFL annotation, hybrid retrieval, topic modeling, and context synthesis.

### Measured state of the source data

All figures measured on 2026-09-14 against `~/.code-insights/data.db`.

Insights, 26,250 rows, all embedded:

| type | rows |
|---|---|
| learning | 10,895 |
| decision | 8,186 |
| summary | 4,176 |
| prompt_quality | 2,993 |

Messages, 282,074 rows across 4,844 sessions:

| slice | rows | size |
|---|---|---|
| empty `content` | 205,276 | |
| of those, carrying only `thinking`/`tool_calls`/`tool_results` | 190,747 | |
| non-empty assistant | 55,531 | 37.9 MB |
| non-empty user | 21,033 | 36.4 MB |
| non-empty system | 234 | 0.1 MB |

Embedding coverage is not partial, it is role-filtered. Every non-empty user message is embedded (21,033 of 21,033, none pending). No non-empty assistant message is embedded (0 of 55,531). The assistant side, where decisions are made and where `evidence` quotes claim to originate, has never been indexed.

### The finding that drives the design

`insights.metadata.evidence` encodes provenance as `"Assistant#3: <quote>"`, a speaker, a turn index, and a quotation. It looks like a citation.

On a random sample of 400 decisions yielding 830 evidence quotes, searching the full text of the insight's own session including `thinking`, `tool_calls`, and `tool_results`:

| outcome | count | share |
|---|---|---|
| quote appears verbatim in session | 81 | 9.8% |
| first six words appear | 21 | 2.5% |
| unresolvable | 728 | 87.7% |

Turn indices do not reliably resolve either. One traced example cites `Assistant#2` in a session whose message at index 2 has zero-length content.

The insights are therefore LLM paraphrases carrying citations that mostly cannot be checked. They are still useful, and the substance is often right, but the corpus cannot be treated as sourced. This is why grounding is the load-bearing part of the design rather than an enhancement.

## Goals

- Ingest sessions, conversation turns, insights, and tool traces into sfl-engine as clauses under a shared parent.
- Compute a grounding score per insight with a citable sibling clause behind it.
- Preserve tool traffic as queryable structure so tool-use patterns can be derived from it later.
- Make `untrusted` mean something an operator can inspect.
- Calibrate the score against hand-labeled data instead of intuition.

## Non-goals

- Evaluating whether the upstream code-insights analyzer writes good insights. That is a separate project and folding it in makes this unshippable.
- Replacing code-insights' own embedding table. sfl-engine embeds what it ingests, through its own `SFL::LLM::Embedder`.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | Ingest both messages and insights | A grounding flag that cannot be explained is just a number. Sibling turns must be retrievable and citable. |
| D2 | New `analytic` register alongside the three SFL-ING-22 registers (`conversation`, `knowledge_base`, `documentation`) | An insight is neither dialogue nor document prose. Follows the `source_code` precedent set on 2026-09-13, which is itself still deferred as SFL-ING-23. |
| D3 | Generalize the `CorpusSource` ref to any `#read`/`#id` responder | A SQLite row is not a file. Adding `RowRef` beside `FileRef` keeps the DB an ordinary origin instead of a special case. |
| D4 | Two-pass: ingest with `untrusted` true, score in a later rake pass | Mirrors the deferred-embedding workflow adopted 2026-09-13. Ingest does not block on embeddings. |
| D5 | Embed assistant messages on the sfl-engine side | Removes a cross-project dependency on a code-insights backfill. One model config, one pipeline. |
| D6 | Score the scorer in Langfuse | τ and the weights are otherwise invented. Gives the Langfuse harness decided 2026-09-13 its first concrete use. |
| D7 | One typed *payload struct* per insight type, carried in `Unit#metadata` | `Core::Types::Unit` is a closed `Dry::Struct` with 7 attributes and is not reopened. Four `Dry::Struct` payloads validate the differing schemas, then serialize into `metadata`, following the precedent in `json_source.rb:79` and `csv_source.rb:62`. `prompt_quality` keeps `dimension_scores` as a Hash and `efficiency_score` as a Float. |
| D8 | `tool_trace` register for the 190,747 tool-only messages | Tool-use patterns are the point, not a side effect. A register makes them queryable for optimizing the harness rather than discarding them as noise. |
| D9 | Exclude the 6 `qwen3-embedding:0.6b` rows | Abandoned experiment, low performance and accuracy. Excluded at ingest so the table-per-dimension layout can assume 768. |

## Dependency order

```
SFL-ING-22   Core::Ports::RegisterProfile + Core::Registers::Catalog   [decided 2026-09-13, unbuilt]
  └─ SFL-CI-00  ref generalization: CorpusSource yields Readables
       └─ SFL-CI-01  Store::CodeInsightsSource (origin, three scopes)
            ├─ SFL-CI-02  :analytic register + AnalyticLoader (4 Unit shapes)
            │    └─ SFL-CI-03  rake insights:reground (pass 2b)
            │         └─ SFL-CI-04  Langfuse grounding eval + calibration
            └─ SFL-CI-05  :tool_trace register + ToolTraceLoader
```

SFL-CI-05 depends only on SFL-CI-01 and can land in parallel with the grounding track.

### What SFL-ING-22 has to accommodate

SFL-ING-22 is a genuine blocker, not a nice-to-have. The register catalog was decided on 2026-09-13 and a grep across `lib/` and `app/` finds no `Catalog` or `RegisterProfile`. Everything below it in the tree is blocked.

This spec adds two registers and four Unit shapes, so it is also the first real consumer of that catalog. The contract SFL-ING-22 ships has to support all of the following, or this work forces a second pass over it:

1. **More than one Unit shape per register.** `:analytic` carries four (`decision`, `learning`, `summary`, `prompt_quality`). A `RegisterProfile` that assumes one shape per register does not fit. The profile resolves a shape from a discriminator on the ref, not from the register alone.
2. **Non-prose fields in a Unit.** `prompt_quality` holds `dimension_scores` (a hash) and `efficiency_score` (a float). Unit shapes cannot assume every field is text.
3. **Registration from outside `Core::Loaders`.** `:analytic` and `:tool_trace` are defined by this ingest work, not by the core loader set. The catalog needs an open registration path so a register is added without editing core.
4. **Origin-independent registers.** Per the ruling of 2026-09-13 that origin and register are independent axes, nothing about `:analytic` may assume a SQLite origin. A future JSONL export of the same insights must route to the same register.
5. **A register that is deliberately not retrieval-facing.** `:tool_trace` exists to be aggregated, not synthesized into prose answers. The profile needs to express that a register is excluded from default retrieval without a special case in the retriever.

Items 1 and 5 are the two most likely to be missed if SFL-ING-22 is built without this spec in hand.

## Architecture

### Ref generalization (SFL-CI-00)

`Core::Ports::CorpusSource` does not exist yet. SFL-ING-16 is still in backlog, so this is not a port edit but an amendment to that card's acceptance criteria, made before it is built.

SFL-ING-16 as written specifies `#each_ref` yielding `FileRef`, and SFL-ING-22 specifies `#analyze(file_ref, services)`. Both need widening by one degree: the port yields a **Ref** answering `#read(limit = nil)`, `#name`, `#extension`, `#content_identity`, `#size_bytes`, `#mtime`, and `#source_id`. `FileRef` is the filesystem and git implementation. `RowRef` is the SQLite implementation, reading one row as a JSON document, with `content_identity` derived from the row's own `id` plus its timestamp.

Doing this before SFL-ING-16 ships costs one word in a signature. Doing it afterward costs a migration of all 13 converted loaders.

### Store::CodeInsightsSource (SFL-CI-01)

One origin, three scopes, one read-only handle:

```
CodeInsightsSource(db)
  ├─ scope :messages     -> RowRef -> conversation register   76,798 units
  ├─ scope :insights     -> RowRef -> analytic register       26,244 units
  └─ scope :tool_traces  -> RowRef -> tool_trace register    190,747 units
                            session = shared parent clause     4,844
```

Insight count is 26,244 rather than 26,250: the 6 `qwen3-embedding:0.6b` rows are excluded per D9.

Opens the telemetry DB with a read-only URI and a `busy_timeout`, so an ingest run can never write to it. `#stats` reports adapter-level exclusions per the convention adopted 2026-09-13:

```ruby
{ routed_tool_trace: 190_747, skipped_bad_metadata: n,
  skipped_empty: n, skipped_wrong_dim: 6 }
```

`routed_tool_trace` is a routing count, not an exclusion — it is reported separately from the skip counters so the two are never confused in a run summary.

The orchestrator folds these into run counters.

### The :analytic register (SFL-CI-02)

`Core::Types::Unit` is a closed `Dry::Struct` with seven attributes (`document_id`, `text`, `heading`, `speaker`, `is_user`, `sent_at`, `metadata`) and this spec does not reopen it. Structured payloads ride in `metadata`, which is the established pattern: `json_source.rb:79` carries a whole record there, `csv_source.rb:62` a whole row.

What D7 adds is that the payload is *validated* rather than a loose Hash. Four `Dry::Struct` payload types under `Core::Types::Insight`, one per insight type, each serialized into `metadata["payload"]` after validation. The schemas genuinely differ, and flattening them to prose discards the structure that justifies the register. `revisit_when` is the clearest case: an expiry condition is useful only if it survives ingest as a typed field rather than a sentence inside a blob.

Common envelope for all four:

```ruby
Unit.new(
  document_id: "insight:#{id}",
  text:        <rendered prose for annotation and embedding>,
  speaker: nil, is_user: false, sent_at: timestamp,
  metadata: {
    "register" => "analytic",
    "insight_type" => type,          # decision | learning | summary | prompt_quality
    "project_name" => .., "confidence" => .., "session_id" => .., "source_tool" => ..,
    "payload" => <payload_struct.to_h>
  }
)
```

Payload bodies:

```ruby
Insight::DecisionPayload      # 8,186
  claim, situation, choice, reasoning,
  alternatives: Array(Hash[option, rejected_because]), trade_offs, revisit_when

Insight::LearningPayload      # 10,895
  takeaway, symptom, root_cause, applies_when, evidence: Array(String)

Insight::SummaryPayload       # 4,176
  claim, outcome

Insight::PromptQualityPayload # 2,993 -- numeric, not prose
  takeaways, findings, message_overhead,
  efficiency_score: Float, dimension_scores: Hash
```

`text` is rendered from the payload per type, because annotation and embedding need prose. The payload remains the queryable form.

`prompt_quality` is what forces requirement 2 on SFL-ING-22: its payload is mostly numeric, so a `RegisterProfile` that assumes one prose shape per register cannot express it.

Whether `metadata["payload"]` is enough or these fields eventually want their own column or table is deferred. It is recorded as an open question rather than settled here.

### The :tool_trace register (SFL-CI-05)

The 205,276 messages with empty `content` are not dialogue, and 190,747 of them carry `thinking`, `tool_calls`, or `tool_results`. Discarding them loses the record of what the harness actually did, which is the part worth optimizing.

```ruby
Unit.new(
  document_id: "trace:#{id}",
  text:        <tool_name plus a truncated argument summary>,
  speaker: nil, is_user: false, sent_at: timestamp,
  metadata: {
    "register" => "tool_trace",
    "session_id" => .., "project_name" => .., "source_tool" => ..,
    "payload" => ToolTracePayload.new(
      tool_name:, arguments:, result_status:,
      result_size:, thinking:, sequence_index:
    ).to_h
  }
)
```

Same envelope rule as `:analytic` — closed `Unit`, validated payload in `metadata`.

The purpose is aggregation, not retrieval: which tools are called, in what order, how often a call fails and is retried, which sequences recur across sessions. That is the raw material for deciding what to automate, and it answers a question the insight corpus cannot, since insights record what was decided rather than what was done.

Consequences worth stating:

- This register is excluded from default retrieval. A tool call is not something to synthesize prose from. That exclusion is requirement 5 on SFL-ING-22.
- It is not embedded. Pass 2a skips `:tool_trace` entirely, which keeps 190,747 units out of the embedding queue and off the cost sheet.
- It shares the session parent clause with messages and insights, so a tool sequence can be read alongside the turns and decisions from the same session.

Tool-use pattern analysis is downstream work and out of scope for this spec. The register exists so that work has something to run against.

### Parent and child

Session is the parent clause, turns and insights are leaves, riding the `parent_clause_id` column added 2026-09-12. This satisfies the ruling of 2026-09-13 that the parent clause is the topic-modeling document unit, and gives the session arm of the coherence metric somewhere to live. No new schema.

## Data flow

### Pass 1: ingest, no embeddings

Embedder is `Null::Embedder` during the walk.

```
POST /ingest -> 202 + run_id                       [SFL-ING-13, as specified]
  CodeInsightsSource(db, read-only)
    ├─ :messages  -> ConversationLoader
    └─ :insights  -> AnalyticLoader
                      |
             Analysis::Engine compiles Units -> clauses + payloads
                      |
   session clause (parent) <- parent_clause_id -┬- message clauses
                                                └- insight clauses
                                                     untrusted = true
                                                     modality_weight = nil
                                                     annotation_source = "code_insights:v1"
```

Ordering is load-bearing: sessions, then messages, then insights. An insight written before its sibling turns has nothing to ground against and pass 2b would score it unfairly.

### Pass 2a: embeddings

`rake embeddings:redrive`, unchanged. No new code. The existing deferred pass covers `:conversation` and `:analytic`, including the 55,531 assistant turns that code-insights never embedded. `:tool_trace` is excluded, keeping 190,747 units out of the queue.

### Pass 2b: rake insights:reground

Two arms that degrade independently:

- `citation_fidelity`. Parse each `evidence` entry as `Speaker#N: quote`. Resolve against sibling conversation clauses under the same `parent_clause_id`. Scored per quote on a three-level scale, taking the highest level that matches: 1.0 for normalized verbatim containment, 0.5 for token overlap above a floor, 0.0 otherwise. The arm's value is the mean across the insight's quotes. Needs no vectors and runs before pass 2a completes.
- `message_cosine`. Max cosine between the insight vector and each sibling message vector, plus cosine against the session centroid as `session_cosine`.

```
grounding       = w1*citation_fidelity + w2*message_cosine + w3*session_cosine
untrusted       = grounding < tau
modality_weight = grounding
grounded_by     = clause_id of the best-matching sibling turn
```

`grounded_by` is what earns the redesign. It is a real clause id, so `ContextSynthesizer`'s citable partition can show the turn behind a claim, and a claim with no defensible turn reads as exactly that rather than as a bare score.

Weights and `tau` are configuration, not constants. See calibration below.

## Observability and evaluation (SFL-CI-04)

Pass 2b runs inside the existing `Core::Ports::Instrumenter` port, which means `Null::Instrumenter` in tests and Langfuse in operation with no branching in the scorer:

```ruby
instrument("insights.reground", {
  clause_id:, session_id:,
  citation_fidelity:, message_cosine:, session_cosine:,
  grounding:, untrusted:, grounded_by:,
  sibling_turns: n, evidence_entries: n
}) { ... }
```

Two properties are asserted by the eval rather than described in comments:

1. **The nil invariant.** `grounding == nil` must never produce `untrusted == false`. Asserted across the whole run so a future weight change cannot quietly violate it.
2. **Grounding is not a truth score.** The dataset carries two independent labels per item: *defensible from the transcript* and *actually correct*. If agreement with "correct" starts tracking as closely as agreement with "defensible", the metric has drifted into pretending to be something it is not. The divergence between the two is the signal being watched.

### Calibration

The 400-row sample in this document is a finding, not a calibration set. The Langfuse dataset replaces it:

- Hand-label a stratified sample across `type`, across projects, and across the resolvable/unresolvable split, for *defensible from transcript*, yes or no.
- Run the scorer as a Langfuse experiment over that dataset.
- Choose `tau` from the precision/recall curve. Fit `w1`, `w2`, `w3` rather than guessing.
- Re-run on every scorer change, so 87.7% becomes a tracked number rather than a one-off measurement.

The labeling is manual and is the real cost of this section. A few hundred items is enough to set `tau`. It cannot be automated, because the ground truth is the operator's judgement about their own sessions.

## Error handling

| Condition | Behavior |
|---|---|
| Telemetry DB locked or in WAL | read-only URI plus `busy_timeout`; ingest never writes to it |
| Malformed `metadata` JSON | skip row, increment `stats[:skipped_bad_metadata]` |
| Tool-only message | route to `:tool_trace`, `stats[:routed_tool_trace]`, expected around 190,747 |
| Insight embedded at 1024 dimensions | skip, `stats[:skipped_wrong_dim]`, expected 6 |
| Malformed embedding vector | `validate_vector!` already fails closed, `lib/sfl/llm/embedder.rb:93` |
| Insight with no sibling turns | `grounding = nil`, `untrusted` stays true. Absence of evidence is not evidence |
| Concurrent ingest run | 409 Conflict with `run_id`, per the decision of 2026-09-13 |
| Pass 2b re-run | idempotent, recomputes from current state, no accumulation |

## Testing

The design splits cleanly along determinism. Everything with a right answer is a unit test; everything requiring judgement is an eval.

### Unit, deterministic

- **Evidence parsing.** `"Assistant#3: quote"` into speaker, index, quote. Table-driven over real malformed samples from the corpus, including missing colon, empty quote, index out of range, and non-list `evidence`.
- **Ref generalization.** `FileRef` and `RowRef` both satisfy the `#read`/`#id` contract. Existing filesystem and git source specs must pass unchanged; that is the regression gate on the port edit.
- **Loader unit-cutting, all four shapes.** `AnalyticLoader` produces the correct Unit shape per insight type with every schema field preserved. `revisit_when` survives round-trip on `decision`; `dimension_scores` and `efficiency_score` survive as Hash and Float on `prompt_quality` rather than being stringified.
- **Shape discrimination.** An insight whose `type` has no registered shape raises rather than falling back to a generic shape, so a new upstream insight type fails loudly instead of silently losing fields.
- **Tool-trace routing.** A message with empty `content` and non-empty `tool_calls` routes to `:tool_trace`, not `:conversation`, and is counted under `routed_tool_trace` rather than a skip counter.
- **Dimension exclusion.** A 1024-dimension insight row is skipped and counted under `skipped_wrong_dim`.
- **Parent/child wiring.** Insights, messages, and tool traces from one session share a `parent_clause_id`; those from different sessions do not.
- **The nil invariant.** Property test: for all inputs where `grounding` is nil, `untrusted` is true. This is also asserted in the eval, deliberately duplicated because it is the invariant most likely to be broken by a well-meaning refactor.
- **`#stats` accounting.** Routed counts plus skipped counts plus ingested counts equal the source row count, across all three scopes. No row is silently lost.
- **Read-only enforcement.** A write attempt against the telemetry handle raises.

### Integration

- Fixture DB built from a small anonymized slice of real telemetry, not synthetic rows. The 87.7% finding exists precisely because synthetic data would have looked fine.
- Full pass 1 then 2a then 2b against the fixture, asserting ordering: an insight is never scored before its sibling turns exist.
- Pass 2b run twice, asserting identical output.

### Eval, judgement

Langfuse experiment over the hand-labeled dataset, as described above. Not part of CI, since it needs a Langfuse endpoint and a labeled set. Run on scorer changes.

## Resolved during review

Three questions raised in the first draft were settled in annotation on 2026-09-14 and are recorded here rather than deleted, so the reasoning survives.

- **`qwen3-embedding:0.6b` rows.** An abandoned experiment; performance and accuracy were both low. Excluded at ingest (D9), so the table-per-dimension layout can assume 768.
- **One Unit shape or four.** Four (D7). The schemas differ materially and `prompt_quality` is numeric.
- **`tool_trace` register.** In scope (D8), as SFL-CI-05. Tool-use patterns are the reason to keep the rows, not a hypothetical later use.

## Open questions

- Whether `:tool_trace` needs its own parent above the session, such as a tool-sequence clause, or whether `sequence_index` on a flat list is enough for the pattern analysis that follows. Deferred until there is a real query to serve.
- Whether `prompt_quality`'s numeric payload wants an SFL annotation pass at all, or should bypass Pass 1 annotation and land as structured data only. Affects cost, since it is 2,993 units.
- Whether `metadata["payload"]` is a sufficient home for the typed payloads long term, or whether `revisit_when` and `dimension_scores` eventually justify their own columns for indexed querying. Deferred until a query needs it.

## Appendix: source schema reference

```sql
insights(id, session_id, project_id, project_name, type, title, content,
         summary, bullets, confidence, source, metadata, timestamp,
         created_at, scope, analysis_version, linked_insight_ids,
         embedding_status)

messages(id, session_id, type, content, thinking, tool_calls, tool_results,
         usage, timestamp, parent_id, embedding_status)

sessions(id, project_id, project_name, project_path, summary, custom_title,
         generated_title, session_character, started_at, ended_at,
         message_count, tool_call_count, git_branch, source_tool, ...)

session_facets(session_id, outcome_satisfaction, workflow_pattern,
               had_course_correction, course_correction_reason,
               iteration_count, friction_points, effective_patterns, ...)
```

`metadata` keys by insight type, with row counts:

- `decision`: situation (8,186), reasoning (8,186), alternatives (8,186), trade_offs (8,184), choice (8,184), revisit_when (8,181), evidence (8,181)
- `learning`: takeaway (10,890), evidence (10,890), root_cause (10,889), applies_when (10,888), symptom (10,834)
- `prompt_quality`: takeaways, message_overhead, findings, efficiency_score, dimension_scores (2,993 each)
- `summary`: outcome (4,155)
