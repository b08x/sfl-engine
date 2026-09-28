Context synthesis is the final reader-facing stage of `sfl-engine`'s retrieval layer. A user submits a natural-language query; the engine does not answer it from raw text, embeddings, or keyword scores. Instead it retrieves a ranked, SFL-annotated evidence block from stored clauses and asks an LLM to compose a cited answer grounded in that evidence. This page documents the architectural position, the retrieval-to-synthesis pipeline, the evidence format, the citation contract, fallback/degradation behavior, and the primary interfaces (`POST /synthesize`, the `context` CLI subcommand, and the TUI Query Console).

---

## Architecture Position

Context synthesis sits at the end of the retrieval slice, downstream of `PgHybridRetriever` and upstream of the answer consumers. It is a single responsibility class with a single public method, `synthesize`. There is no pipeline of its own — it owns only the step that turns a retrieval result into a cited, LLM-composed answer.

```mermaid
flowchart TD
    Query[User Query] --> Retriever[PgHybridRetriever]
    Retriever --> Ranked[Ranked Clause Rows<br>RRF merge + scalar filters]
    Ranked --> Partition[Citable partition<br>(untrusted/fallback excluded)]
    Partition --> Format[Numbered evidence block<br>mood/tenor/modality/process-source]
    Format --> Synthesizer[LLM ContextSynthesizer<br>DSPy SynthesisSignature]
    Synthesizer --> Result[SynthesisResult<br>answer · cited_clause_ids · confidence]
    Result --> Answer[API/CLI/TUI consumer]
```

**Why this structure?** The synthesizer is deliberately segregated from retrieval. RRF is a deterministic scoring merge; synthesis is an LLM call that must never run against unfiltered, fallback-annotated, or out-of-range clauses. Keeping the evidence block construction inside the synthesis class — rather than in the retriever — makes the "citable/untrusted" contract a first-class part of the result instead of a retrieval side effect.

The dependency chain is explicit in the composition root: `SFL::API::Context.build` wires a `Retrieval::ContextSynthesizer` with a fresh `Store::PgHybridRetriever`, a `boot_result.lm_factory.for(:context_synthesis)` LM, a `PgClauseStore`, a `breaker`, `instrumenter`, and `logger` [[lib/sfl/api/context.rb#L46-L78](lib/sfl/api/context.rb#L46-L78)].

**Sources:** [lib/sfl/api/context.rb](lib/sfl/api/context.rb#L46-L78); [docs/architecture-diagrams.md](docs/architecture-diagrams.md#L14-L16); [lib/sfl/core/pipeline.rb](lib/sfl/core/pipeline.rb#L1-L20)

---

## The Retrieval-to-Synthesis Pipeline

### 1. Input: RetrievalQuery

`ContextSynthesizer#synthesize` does not take a raw query string. It takes a typed `Core::Types::RetrievalQuery` that carries three responsibilities, all enforced by Dry::Struct schema strictness [[lib/sfl/core/types/retrieval_query.rb](lib/sfl/core/types/retrieval_query.rb)]:

| Field | Type | Default | Purpose |
|---|---|---|---|
| `query` | `String` | — | The user's analytical question |
| `limit` | `Integer` | `10` | Final row budget returned to the synthesizer |
| `filters` | `RetrievalFilters` | empty | Scalar stance filters for the retrieval arms |

`RetrievalFilters` is itself a strict Dry::Struct with optional scalar attributes only: `mood`, `min_modality`/`max_modality`, `min_tenor`/`max_tenor`, `process_type`, and `source_type` [[lib/sfl/core/types/retrieval_filters.rb](lib/sfl/core/types/retrieval_filters.rb)]. Every attribute is optional and defaults to `nil`, meaning a filter-free query is a valid query — not a degenerate one.

### 2. Retrieval: PgHybridRetriever with Scalar Filters

The retriever is the hybrid arm: semantic search over pgvector embeddings plus Postgres full-text keyword search, merged with Reciprocal Rank Fusion (RRF, K = 60). A deliberate correctness fix (F8) applies every RetrievalFilters attribute into the `.where(...)` of **both** search arms before their `.order`/`.limit`, rather than merging unfiltered candidates and filtering afterwards. This prevents a selective filter (e.g. mood: "imperative") from starving the final result to fewer than `limit` rows [[lib/sfl/store/pg_hybrid_retriever.rb](lib/sfl/store/pg_hybrid_retriever.rb)].

Result rows are `Core::Types::RetrievalResult` — a typed Dry::Struct that **inlines** mood, tenor, process_type, modality_weight, annotation_source, untrusted, and parent_clause_id into every ranked hit [[lib/sfl/core/types/retrieval_result.rb](lib/sfl/core/types/retrieval_result.rb)]. This avoids a per-clause N+1 lookup in the synthesizer; the metadata is already sitting in the same joined row the search arms returned.

### 3. Partition: Citable vs. Excluded

`ContextSynthesizer` splits the ranked rows into two groups [[lib/sfl/retrieval/context_synthesizer.rb#L88-L98](lib/sfl/retrieval/context_synthesizer.rb#L88-L98)]:

- **Citable**: rows that either carry a trusted annotation source or are explicitly opted into with `include_fallback: true`. A row is untrusted when `row.untrusted` is true or when its annotation source is a fallback/stub.
- **Excluded**: rows that carry a fallback/stub interpersonal annotation. These are reported in a **data-quality preamble**, not silently dropped. The preamble is `nil` when nothing is excluded; otherwise it reads `"_Data Quality: N/M retrieved clauses excluded due to fallback annotation._"`.

The partition logic is defensive: missing `annotation_source` (rows stored before that column existed) counts as trusted, and the literal `"human"` string is treated as trusted alongside `"llm"` — a reviewer-supplied correction is not a compiler-substituted default [[lib/sfl/retrieval/context_synthesizer.rb#L132-L143](lib/sfl/retrieval/context_synthesizer.rb#L132-L143)].

### 4. Format: Numbered Evidence Block

The citable rows are rendered into a numbered, SFL-annotated string with this exact format per row [[lib/sfl/retrieval/context_synthesizer.rb#L152-L162](lib/sfl/retrieval/context_synthesizer.rb#L152-L162)]:

```
[1] <clause text>
    (mood=<mood>, tenor=<tenor>, modality=<modality_weight>, process=<process_type>; source: <document_id>)
[2] <clause text>
    ...
```

Each clause is numbered starting at 1. The evidence block is the single input contract to the LLM: the numbered index is what the synthesizer must cite, and it is the only thing the caller later maps back to clause ids.

### 5. LLM Synthesis: DSPy Signature

The actual synthesis call is made through a `DSPy::Predict` wrapper over `LLM::Signatures::SynthesisSignature` [[lib/sfl/llm/synthesizers/context_synthesizer.rb](lib/sfl/llm/synthesizers/context_synthesizer.rb#L8-L19)]. This signature is the structured-output contract for evidence-grounded query synthesis; it replaced the legacy DSPy `SynthesisSignature` output block (track decision 7) [[lib/sfl/llm/signatures/synthesis_signature.rb](lib/sfl/llm/signatures/synthesis_signature.rb#L12-L26)].

The signature fixes three outputs:

| Output | Type | Semantics |
|---|---|---|
| `answer` | `String` | Grounded answer, composed from the numbered evidence |
| `cited_clause_numbers` | `T::Array[Integer]` | Evidence numbers actually used, a subset of the input numbering |
| `confidence` | `Float` | 0.0–1.0; lower when evidence is thin or conflicting |

`ResponseSymbolizer.call` post-processes the raw `DSPy` output hash into the symbol-keyed contract [[lib/sfl/llm/synthesizers/context_synthesizer.rb](lib/sfl/llm/synthesizers/context_synthesizer.rb#L15-L18)].

**Sources:** [lib/sfl/retrieval/context_synthesizer.rb](lib/sfl/retrieval/context_synthesizer.rb#L58-L180); [lib/sfl/store/pg_hybrid_retriever.rb](lib/sfl/store/pg_hybrid_retriever.rb#L1-L163); [lib/sfl/core/types/retrieval_query.rb](lib/sfl/core/types/retrieval_query.rb); [lib/sfl/core/types/retrieval_filters.rb](lib/sfl/core/types/retrieval_filters.rb); [lib/sfl/core/types/retrieval_result.rb](lib/sfl/core/types/retrieval_result.rb); [lib/sfl/llm/synthesizers/context_synthesizer.rb](lib/sfl/llm/synthesizers/context_synthesizer.rb); [lib/sfl/llm/signatures/synthesis_signature.rb](lib/sfl/llm/signatures/synthesis_signature.rb)

---

## The SynthesisResult Contract

Every synthesis path returns a `Core::Types::SynthesisResult` — a Dry::Struct with these attributes [[lib/sfl/core/types/synthesis_result.rb](lib/sfl/core/types/synthesis_result.rb)]:

| Attribute | Type | Default | Meaning |
|---|---|---|---|
| `query` | `String` | — | The original query, echoed back |
| `answer` | `String`, optional | — | The LLM-composed, cited answer (nil on failure/empty) |
| `cited_clause_ids` | `Array<String>` | `[]` | Clause ids mapped from the cited clause numbers (out-of-range numbers dropped, never trusted) |
| `clauses` | `Array<Hash>` | `[]` | The full retrieved set, including excluded rows |
| `retrieved_count` | `Integer` | — | Number of clauses actually retrieved before the citable partition |
| `confidence` | `Float`, optional | — | LLM-reported confidence |

The `cited_clause_ids` mapping is **defensive by construction**: `ContextSynthesizer#map_citations` treats a LLM number as valid only when it is a positive integer within the citable list, and uses `filter_map` so out-of-range numbers are dropped rather than promoted to fabricated clause ids [[lib/sfl/retrieval/context_synthesizer.rb#L127-L130](lib/sfl/retrieval/context_synthesizer.rb#L127-L130)].

**Sources:** [lib/sfl/core/types/synthesis_result.rb](lib/sfl/core/types/synthesis_result.rb); [lib/sfl/retrieval/context_synthesizer.rb](lib/sfl/retrieval/context_synthesizer.rb#L43-L53)

---

## Degradation and Fallback Behavior

Synthesis is the **only** LLM-calling stage in the codebase that is *not* internally degraded [[lib/sfl/cli.rb](lib/sfl/cli.rb#L95-L97) and the project overview corroborates this]. A failed synthesis call (a `Dry::Struct::Error` from malformed output) propagates as a degraded result: `answer` is `nil`, `confidence` is `nil`, but the `clauses` and `retrieved_count` are still fully populated and returnable to the caller [[lib/sfl/retrieval/context_synthesizer.rb#L112-L125](lib/sfl/retrieval/context_synthesizer.rb#L112-L125)]. The comment in the source is explicit: *"Unlike Pass 2, a failed synthesis call propagates — there is no useful default 'answer'"* [[lib/sfl/retrieval/context_synthesizer.rb#L50-L52](lib/sfl/retrieval/context_synthesizer.rb#L50-L52)].

Two orthogonal fallback dimensions exist:

1. **Fallback/annotation-source filter** (`include_fallback:`): when false (default), clauses whose interpersonal annotation came from the Pass 2 degradation ladder (`annotation_source: "fallback"` or `"stub"`) are excluded from the evidence block and from citation. They still appear in `clauses:` — the full retrieved set is always reported. This prevents a fallback annotation (e.g. a 0.5 placeholder) from silently grounding an answer [[lib/sfl/retrieval/context_synthesizer.rb](lib/sfl/retrieval/context_synthesizer.rb#L60-L68)].
2. **Anomaly expansion** (`expand_ancestors:`): when true and a citable row is a child chunk (`parent_clause_id` present), its evidence text is widened to include the ancestor chain (root first). This requires `clause_store:` to be injected; otherwise it is a no-op and the row's own text is used [[lib/sfl/retrieval/context_synthesizer.rb#L166-L180](lib/sfl/retrieval/context_synthesizer.rb#L166-L180)].

The open الترتیب is that synthesis is the one LLM call that does not degrade: when the LLM returns malformed output, the caller is guaranteed a non-fabricated, evidence-backed response, but the `answer` field is `nil` and the caller must decide what to do next [[lib/sfl/cli.rb](lib/sfl/cli.rb#L95-L97)].

**Sources:** [lib/sfl/retrieval/context_synthesizer.rb](lib/sfl/retrieval/context_synthesizer.rb#L50-L68); [lib/sfl/cli.rb](lib/sfl/cli.rb#L95-L97); [docs/project-overview.md](docs/project-overview.md#L14-L17)

---

## Interfaces

### HTTP API: `POST /synthesize`

Wire: `app/routes/synthesize.rb` → `SFL::API::Context.build` → `ctx.synthesizer.synthesize` [[app/routes/synthesize.rb](app/routes/synthesize.rb)]. Body:

| Field | Type | Default | Meaning |
|---|---|---|---|
| `query` | `String` | required | The analytical query |
| `filters` | `Hash` | `{}` | `mood`, `min/max_tenor`, `min/max_modality`, `process_type`, `source_type` |
| `limit` | `Integer` | `10` | Clamped to a minimum of 1 |
| `include_fallback` | `Boolean` | `false` | Opt in to fallback-annotated clauses |
| `expand_ancestors` | `Boolean` | `false` | Include ancestor chain text on child chunks |

Response: `Core::Wire.dump(SynthesisResult)` as JSON.

### CLI: `sfl-analyze context <query>`

The `context` subcommand is one of four `sfl-analyze` subcommands [[lib/sfl/cli.rb](lib/sfl/cli.rb)]. Its options mirror retrieval: `--limit N`, `--mood MOOD`, `--min-tenor F`, `--max-tenor F`, `--min-modality F`, `--max-modality F` [[lib/sfl/cli.rb#L99-L111](lib/sfl/cli.rb#L99-L111)]. The `run_context` driver wires a fresh retriever + `context_synthesis` LM, calls `synthesizer.synthesize`, and prints:

- when `retrieved_count` is zero: a hint to ingest documents first (`sfl-analyze documentation <path> --store`).
- when `answer` is `nil`: a degradation message and the raw evidence.
- when `answer` is present: the answer with confidence, plus a per-clause evidence printout [[lib/sfl/cli.rb](lib/sfl/cli.rb#L86-L114)].

Optional `--output-dir` writes `context_synthesis.json` with the full `SynthesisResult` hash [[lib/sfl/cli.rb](lib/sfl/cli.rb#L106-L114)].

### TUI: Query Console

Phase 2 of the terminal UI wires this to `Analysis::ContextSynthesizer` and `Store::PgHybridRetriever` [[lib/sfl/tui/workspaces/query_console.rb](lib/sfl/tui/workspaces/query_console.rb)]. The workspace renders a three-pane layout: a recent-query session ring buffer, the synthesized answer, and a telemetry pane showing `rrf_score` per clause, plus a separate retrieval-trace pane for semantic vs keyword rank [[lib/sfl/tui/workspaces/query_console.rb](lib/sfl/tui/workspaces/query_console.rb),(1)-(34)].

The API composition root `SFL::API::Context.build` is the single wiring point that the HTTP server and the CLI actually consume; the TUI consumes it through `AppContext` [[lib/sfl/tui/app_context.rb](lib/sfl/tui/app_context.rb)].

**Sources:** [app/routes/synthesize.rb](app/routes/synthesize.rb); [lib/sfl/cli.rb](lib/sfl/cli.rb#L59-L114); [lib/sfl/tui/workspaces/query_console.rb](lib/sfl/tui/workspaces/query_console.rb); [lib/sfl/api/context.rb](lib/sfl/api/context.rb#L53-L78); [lib/sfl/api/server.rb](lib/sfl/api/server.rb#L151-L163)

---

## Design Rationale

- **A typed request/response contract replaces raw hashes.** `RetrievalQuery`, `RetrievalFilters`, the `RetrievalResult` row, and `SynthesisResult` are all strict Dry::Structs. This gives the LLM-facing and API-facing surfaces a real, introspectable schema instead of a loose Hash, so a typo'd key raises at construction time rather than silently no-oping downstream [[lib/sfl/core/types/retrieval_query.rb](lib/sfl/core/types/retrieval_query.rb)].
- **The evidence block is the synthesis input contract.** Numbered clauses with SFL annotations (mood, tenor, modality, process type, source) are what the LLM reasons over. The numbering is the citation anchor.
- **Out-of-range citations are never trusted.** `map_citations` only accepts positive integers within the citable list, and drops the rest — "out-of-range numbers are dropped (don't trust LLM references)" [[lib/sfl/retrieval/context_synthesizer.rb](lib/sfl/retrieval/context_synthesizer.rb#L127-L130)].
- **Fallback annotations are surfaced, not hidden.** The data-quality preamble and the `include_fallback` flag keep the degradation ladder visible to the caller and the caller's consumer [[lib/sfl/retrieval/context_synthesizer.rb](lib/sfl/retrieval/context_synthesizer.rb#L60-L68)].
- **Synthesis does not degrade the way Pass 2 does.** A malformed LLM response returns evidence without an answer, and propagates as a `nil` answer rather than a fabricated one [[lib/sfl/cli.rb](lib/sfl/cli.rb#L95-L97)].

**Sources:** [lib/sfl/retrieval/context_synthesizer.rb](lib/sfl/retrieval/context_synthesizer.rb); [lib/sfl/core/types/retrieval_query.rb](lib/sfl/core/types/retrieval_query.rb); [lib/sfl/llm/signatures/synthesis_signature.rb](lib/sfl/llm/signatures/synthesis_signature.rb); [docs/architecture-diagrams.md](docs/architecture-diagrams.md); [docs/superpowers/specs/2026-09-14-code-insights-telemetry-ingest-design.md](docs/superpowers/specs/2026-09-14-code-insights-telemetry-ingest-design.md:L15)