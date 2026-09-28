`PostgresHybridRetriever` is the retrieval backbone of the SFL Engine. It answers a free-text query over 8.5+ million annotated clauses by combining dense semantic search (pgvector cosine similarity) with lexical keyword search (Postgres full-text search), merging the two ranked candidate pools with **Reciprocal Rank Fusion (RRF)** in Ruby. Every returned clause additionally carries the SFL scalar stance fields (mood, tenor, modality, process_type, annotation_source) as first-class output attributes.

**Scope of this page**: `Store::PgHybridRetriever`, the `RetrievalFilters`/`RetrievalQuery` value types, `ClauseFilters`, the RRF merge algorithm, and how the result flows into `Retrieval::ContextSynthesizer`.

## How the two arms are built

`PgHybridRetriever` (`lib/sfl/store/pg_hybrid_retriever.rb:22`) implements `Core::Ports::Retriever` (`lib/sfl/core/ports/retriever.rb:13`), so any future backend (in-memory, search-service) can replace it without changing the API surface.

**Semantic arm** — `semantic_search` (`lib/sfl/store/pg_hybrid_retriever.rb:58`). The query string is embedded by the injected `Core::Ports::Embedder` (`lib/sfl/llm/embedder.rb:23`) and encoded with `Pgvector.encode`. The scope is already joined against `clauses`, `ideational_payloads`, and `interpersonal_payloads` (`pg_hybrid_retriever.rb:86-90`), then ordered by pgvector cosine distance `embedding <=> ?` (`pg_hybrid_retriever.rb:67`). The HNSW index for cosine is defined at `db/migrations/004_create_embeddings.rb:29`. If the embedder returns an empty vector (the contract for "nothing to embed"), the arm returns `[]` instead of sending a malformed `<=>` comparison to Postgres (`pg_hybrid_retriever.rb:66`).

**Keyword arm** — `keyword_search` (`lib/sfl/store/pg_hybrid_retriever.rb:73`). Leverages the same joined scope but adds a Postgres full-text predicate:

```sql
to_tsvector('simple', clauses.text) @@ plainto_tsquery('simple', ?)
```

ranked by `ts_rank(...)` descending (`pg_hybrid_retriever.rb:78-80`). No embedding means the keyword arm runs independently — dense and sparse signals are never blocked by the absence of one another.

**Scalar filter arms** — `ClauseFilters.apply` (`lib/sfl/store/clause_filters.rb:27`) pushes every non-nil `RetrievalFilters` attribute into the SQL `WHERE` of *both* arms before `.order`/`.limit` (`pg_hybrid_retriever.rb:62` `pg_hybrid_retriever.rb:74`). The per-field lambda table is:

| Filter | SQL |
|---|---|
| `mood` | `interpersonal_payloads.mood = v` |
| `source_type` | `clauses.source_type = v` |
| `process_type` | `ideational_payloads.process_type = v` |
| `min_modality` | `modality_weight >= v` |
| `max_modality` | `modality_weight <= v` |
| `min_tenor` | `tenor >= v` |
| `max_tenor` | `tenor <= v` |

`CANDIDATE_MULTIPLIER = 3` (`pg_hybrid_retriever.rb:26`) sets `candidate_limit = query.limit * 3`. Each arm fetches up to that window before the RRF merge (`pg_hybrid_retriever.rb:48`). By contrast, the legacy retriever fetched `limit * 3` rows per arm **UNFILTERED**, merged, filtered, then `.first(limit)` — a selective filter could starve the final result. The v2 fix applies every filter to the SQL `WHERE` of both arms, so the candidate pool is already filter-matching (`pg_hybrid_retriever.rb:11`).

**Test to prove the F8 fix**: 15 high-relevance non-matching clauses plus 2 low-relevance matching clauses, `limit: 3`, `mood: "imperative"`. An unfiltered `limit*3=9` window would have surfaced zero matching rows; the filter-in-SQL implementation returns exactly `[imperative-0, imperative-1]` (`spec/store/pg_hybrid_retriever_spec.rb:80-111`).

Sources: `SFL::Store::PgHybridRetriever` (`lib/sfl/store/pg_hybrid_retriever.rb#L1-L163`), `SFL::Store::ClauseFilters` (`lib/sfl/store/clause_filters.rb#L1-L44`), `SFL::Core::Ports::Retriever` (`lib/sfl/core/ports/retriever.rb#L1-L24`), `SFL::Core::Types::RetrievalFilters` (`lib/sfl/core/types/retrieval_filters.rb#L1-L45`), `SFL::Core::Types::RetrievalQuery` (`lib/sfl/core/types/retrieval_query.rb#L1-L25`), spec (`spec/store/pg_hybrid_retriever_spec.rb#L1-L206`).

## The RRF merge in Ruby

RRF is a library-agnostic, rank-based fusion formula: `score = 1 / (RRF_K + rank)`. It was chosen because it is **monotone** (relative order within each arm is preserved), **robust** (dense and sparse signals compensate each other without being normalized by score magnitude), and **cheap** (no cross-encoder pass required). `RRF_K = 60` is the standard constant, same as legacy (`pg_hybrid_retriever.rb:25`).

The merge is a single cumulative hash over `clause_id` (`pg_hybrid_retriever.rb:121-129`):

1. `accumulate_rrf` (`pg_hybrid_retriever.rb:133-140`) walks each arm and adds `1.0 / (RRF_K + rank)` to that `clause_id`'s running `rrf_score`. The rank key (`semantic_rank` or `keyword_rank`) is `idx + 1` from `each_with_index` after `.limit` (`pg_hybrid_retriever.rb:69-71`).
2. Duplicate `clause_id`s (appear in both arms) accumulate both terms and rank above singles.
3. Results are sorted by `-rrf_score` descending and capped at `query.limit` (`pg_hybrid_retriever.rb:143-144`).

**Why RRF stays in Ruby**: the merged set is at most `2 × limit × 3` rows, all pre-filtered and shaped identically by `result_columns` (`pg_hybrid_retriever.rb:107-118`), so pushing the RRF SQL would add no performance and only complexity.

Sources: `lib/sfl/store/pg_hybrid_retriever.rb#L1-L163`, `spec/store/pg_hybrid_retriever_spec.rb#L40-L63`.

## What the result row looks like

`RetrievalResult` (`lib/sfl/core/types/retrieval_result.rb:17`) is a typed `Dry::Struct` — a typo'd key raises at construction rather than silently no-op filtering, matching the F-track requirement (`retrieval_filters.rb:L6-L9`). `PgHybridRetriever` inlines the SFL scalars onto the row (`pg_hybrid_retriever.rb:107-118`): `mood`, `tenor`, `modality_weight`, `annotation_source`, `untrusted`, `process_type`, `parent_clause_id`. Accepting this means `ContextSynthesizer` never needs a second per-clause DB round-trip to determine which clauses are citable (`context_synthesizer.rb:L14-L16`).

Two adjacency fields matter for downstream consumers:

- `parent_clause_id` — the `AnnotatedClause#id` of the parent chunk this clause belongs to; `null` for root/top-level clauses (`retrieval_result.rb:L42-L44`). `ContextSynthesizer` uses it to widen citable child evidence with its ancestor chain when `expand_ancestors: true` (`context_synthesizer.rb:L166-L179`).
- `annotation_source` + `untrusted` — used by `partition_citable` to drop fallback/stub-sourced clauses from LLM-visible evidence while still reporting them in `retrieved_count` (`context_synthesizer.rb:L99-L115`).

Sources: `lib/sfl/core/types/retrieval_result.rb#L1-L44`, `lib/sfl/retrieval/context_synthesizer.rb#L1-L180`, `lib/sfl/store/pg_hybrid_retriever.rb#L107-L118`.

## The HTTP contract and how it is wired

`POST /retrieve` (`app/routes/retrieve.rb:7-15`) deserializes a JSON body into `RetrievalQuery` + `RetrievalFilters`, then calls `ctx.retriever.retrieve(...)`:

| Field | Type | Notes |
|---|---|---|
| `query` | `String` | required; empty raises `ArgumentError` |
| `limit` | `Integer` | default `10`, minimum 1 |
| `filters.mood` | `MoodType` | declarative/interrogative/imperative |
| `filters.source_type` | `String` | free-form provenance tag |
| `filters.process_type` | `ProcessType` | ideational process class |
| `filters.min_modality` | `Float` | `0.0-1.0` |
| `filters.max_modality` | `Float` | `0.0-1.0` |
| `filters.min_tenor` | `Float` | `0.0-1.0` |
| `filters.max_tenor` | `Float` | `0.0-1.0` |

`SFL::API::Context.build` (`lib/sfl/api/context.rb:56-83`) wires two `PgHybridRetriever` instances — one for `/retrieve`, one for `ContextSynthesizer` (`context.rb:67` and `:69`) — sharing the same `boot_result.db` and `boot_result.embedder`.

Sources: `app/routes/retrieve.rb#L1-L18`, `lib/sfl/api/context.rb#L1-L84`, `lib/sfl/core/types/retrieval_query.rb#L1-L25`, `lib/sfl/core/types/retrieval_filters.rb#L1-L45`.

## Where it sits in the pipeline

```
POST /retrieve  →  ctx.retriever.retrieve(RetrievalQuery)
                            │
        ┌───────────────────┴───────────────────┐
        ▼                                       ▼
semantic_search (pgvector cosine)       keyword_search (to_tsvector/ts_rank)
        │                                       │
        ▼                                       ▼
   RRF merge in Ruby  ──→  Array<RetrievalResult> sorted by rrf_score
                            │
                            ▼
              ContextSynthesizer.synthesize
              (partition citable vs fallback, LLM call)
```

The retrieval slice is the bridge between the stored `AnnotatedClause` corpus and the LLM synthesis layer. `Pipeline#compile` (`lib/sfl/core/pipeline.rb:90-94`) writes clauses to `PgClauseStore`, then `PgEmbeddingStore#replace_document` (`lib/sfl/store/pg_embedding_store.rb:66`) writes 768-dim vectors; the retrieve path reads those same vectors back through the HNSW cosine index.

Sources: `lib/sfl/store/pg_hybrid_retriever.rb#L1-L163`, `lib/sfl/core/pipeline.rb#L1-L265`, `lib/sfl/store/pg_embedding_store.rb#L1-L139`.

## What is intentionally missing

- **No `Core::Ports::Reranker`**. RRF is fused inline inside `PgHybridRetriever` (`pg_hybrid_retriever.rb:121-140`) rather than extracted into a `Retrieval::Rerankers::RrfReranker` — the alignment spec explicitly defers it until a re-ranking need is demonstrated (`docs/refactor/EMBEDDING-HEXAGON-USER-STORIES.md:L178-L180`). The `Reranker` port remains a documented TODO.
- **No `bm25f` or cross-encoder**. `Gemfile:L108` (bm25f) and `Gemfile:L209` (informers) are declared but have zero call sites; the inline RRF + `ts_rank` lexical arm remains the lexical strategy.