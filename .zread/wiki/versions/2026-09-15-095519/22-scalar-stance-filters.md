Scalar Stance Filters are the typed, SQL-pushed retrieval filters that bind SFL metafunction scalars (mood, modality, tenor, process_type) and provenance (source_type) to Postgres queries. They live in `lib/sfl/store/clause_filters.rb` (as `SFL::Store::ClauseFilters`), are type-checked at construction by `SFL::Core::Types::RetrievalFilters`, and are applied as SQL `.where(...)` clauses on both arms of the hybrid retriever before RRF merging. This page documents the filter catalog, the typed struct, the lambda-table application pattern, how the filters are fed into retrieval, and the trust-based exclusion layer that sits on top of the retrieved set.

## Filter Catalog and SQL Application

`SFL::Store::ClauseFilters` defines a frozen hash of 1-arity procs, one per retrieval filter attribute:

```ruby
FIND_ALL_FILTERS = {
  mood: -> (v) { { Sequel[:interpersonal_payloads][:mood] => v } },
  min_modality: -> (v) { Sequel[:interpersonal_payloads][:modality_weight] >= v },
  max_modality: -> (v) { Sequel[:interpersonal_payloads][:modality_weight] <= v },
  min_tenor: -> (v) { Sequel[:interpersonal_payloads][:tenor] >= v },
  max_tenor: -> (v) { Sequel[:interpersonal_payloads][:tenor] <= v },
  process_type: -> (v) { { Sequel[:ideational_payloads][:process_type] => v } },
  source_type: -> (v) { { Sequel[:clauses][:source_type] => v } },
}.freeze
```

Each filter maps to a contiguous scalar column in one of three joined tables:
- **interpersonal_payloads** (mood, modality_weight, tenor) — the interpersonal metafunction scalars
- **ideational_payloads** (process_type) — the ideational metafunction scalar
- **clauses** (source_type) — the provenance tag

`ClauseFilters.apply` takes a `Sequel::Dataset` (already joined against `clauses`, `ideational_payloads`, `interpersonal_payloads`) and reduces it by applying one `#where` per non-nil filter attribute, using the table-qualified lambda to avoid ambiguity across joined tables. The dataset-driven design means the same filter table is reusable by other features (e.g., the corpus browser's `find_all` endpoint) without duplicating SQL.

Sources: `lib/sfl/store/clause_filters.rb` `db/migrations/005_add_source_type_to_clauses.rb`

## Typed RetrievalFilters Struct

`SFL::Core::Types::RetrievalFilters` is a Dry::Struct that enforces the scalar filter contract:

- **Every attribute is optional and defaults to nil** — `RetrievalFilters.new` alone is a valid, filter-free query.
- **`schema.strict` is required** — a typo'd key like `:mod` instead of `:mood` raises `Dry::Struct::Error::UnknownKeywordError` at construction, whereas legacy's `Hash#[]` lookup silently ignored unknown keys.
- **Validated against existing enums/constraints** — `MoodType`, `TenorValue`, `ModalityWeight`, and `ProcessType` enums reject bad values rather than silently matching nothing.
- **`source_type` is a free-form String** — it is not constrained to an enum because legacy never fixed a closed set (`"chat_native"`, `"vault_markdown"`, `"api"`, ... grow without a fixed set).

The struct's strictness is the F-track requirement: the retrieval slice card explicitly requires typed filters over legacy's raw `Hash`, because type errors must fail fast at construction, not silently at query time.

Sources: `lib/sfl/core/types/retrieval_filters.rb`

## Application in PgHybridRetriever

`SFL::Store::PgHybridRetriever` builds the semantic and keyword candidate sets by first applying `ClauseFilters.apply` to the joined scope **before** ordering and limiting:

```ruby
def semantic_search(query_text, limit, filters)
  vector = Pgvector.encode(@embedder.embed(query_text))
  return [] if vector.empty?

  scope = ClauseFilters.apply(joined_from_embeddings, filters)
  scope.order(Sequel.lit("embedding <=> ?", vector)).limit(limit).select(*result_columns).to_a
end

def keyword_search(query_text, limit, filters)
  scope = ClauseFilters.apply(joined_from_clauses, filters)
  scope.where(Sequel.lit("to_tsvector('simple', clauses.text) @@ plainto_tsquery('simple', ?)", query_text))
    .order(Sequel.lit("ts_rank(...) DESC")).limit(limit).select(*result_columns).to_a
end
```

This is a deliberate **F8 fix** versus the legacy `HybridRetriever`: the legacy implementation ran both search arms UNFILTERED at `limit * 3`, RRF-merged, THEN filtered the merged set, THEN took `.first(limit)`. A selective filter (e.g., mood: "imperative" against a mostly-declarative corpus) could therefore starve the final result to fewer than `limit` rows even when matching rows existed deeper in the corpus that were never fetched. Here, `ClauseFilters.apply` pushes every `RetrievalFilters` attribute into the SQL `.where(...)` of both arms before `.order`/`.limit`, so the `limit * 3` candidate pool per arm is already filter-matching. The RRF merge itself stays in Ruby — a small in-memory merge over at most `2 * (limit * 3)` rows, with no need to push the merge into SQL as well.

Both arms emit the same `result_columns` (clause_id, text, document_id, parent_clause_id, mood, tenor, modality_weight, annotation_source, untrusted, process_type). RRF combines them by reciprocal rank (`1 / (RRF_K + rank)` with `RRF_K = 60`), sorts by descending `rrf_score`, and takes the top `query.limit` rows. The `build_result` step maps each row to a `Core::Types::RetrievalResult` with all scalar fields inlined.

Sources: `lib/sfl/store/pg_hybrid_retriever.rb`

## RetrievalFilters Attribute Reference

| Filter Attribute | SQL Column | Direction | Type |
|---|---|---|---|
| `mood` | `interpersonal_payloads.mood` | equality | `MoodType` |
| `min_modality` | `interpersonal_payloads.modality_weight` | `>=` | `ModalityWeight` |
| `max_modality` | `interpersonal_payloads.modality_weight` | `<=` | `ModalityWeight` |
| `min_tenor` | `interpersonal_payloads.tenor` | `>=` | `TenorValue` |
| `max_tenor` | `interpersonal_payloads.tenor` | `<=` | `TenorValue` |
| `process_type` | `ideational_payloads.process_type` | equality | `ProcessType` |
| `source_type` | `clauses.source_type` | equality | `String` (free-form) |

All attributes are nullable at construction; any non-nil value is applied as an SQL predicate.

Sources: `lib/sfl/core/types/retrieval_filters.rb` `lib/sfl/store/clause_filters.rb`

## The Trust Layer Above Retrieval

`SFL::Retrieval::ContextSynthesizer` (port of the legacy `Compiler::ContextSynthesizer`) sits on top of `PgHybridRetriever` and adds a **data-quality exclusion** gate before synthesis:

```ruby
def partition_citable(rows, include_fallback)
  citable = rows.select { |row| (include_fallback || llm_sourced?(row)) && !row.untrusted }
  [citable, data_quality_preamble(rows.size - citable.size, rows.size)]
end

private def llm_sourced?(row)
  source = row.annotation_source
  source.nil? || Core::Types::TRUSTED_ANNOTATION_SOURCES.include?(source)
end

TRUSTED_ANNOTATION_SOURCES = %w[llm human].freeze
```

Three scalar/state rules determine citability:
1. A row whose `annotation_source` is `nil` (pre-column rows) is treated as trusted by default — a defensive fallback for rows stored before the column existed.
2. `"human"` counts as trusted alongside `"llm"` — a reviewer-supplied correction is not a compiler-substituted default.
3. Rows flagged `untrusted` are always excluded (defensive, e.g., chunk artifacts flagged by the chunk artifact detector).

When `include_fallback` is false (default), rows whose interpersonal annotation came from the Pass 2 degradation ladder (`annotation_source` "fallback"/"stub") are excluded from the evidence the LLM sees and from citation references — a fallback `0.5` should not silently ground an answer. They still appear in the full `clauses:` array reported to the caller. A `data_quality_preamble` is prepended to the synthesized answer when any rows were excluded.

Sources: `lib/sfl/retrieval/context_synthesizer.rb` `lib/sfl/core/types/trusted_annotation_sources.rb`

## Data Flow: Filter Construction to Retrieval

1. **Construction** — Caller builds `Core::Types::RetrievalFilters` with any subset of `mood`, `min_modality`, `max_modality`, `min_tenor`, `max_tenor`, `process_type`, `source_type`. Dry::Struct enforces types and rejects unknown keys.
2. **Pipeline wiring** — `SFL::API::Context.build` injects a `PgHybridRetriever` (wired with `db` and an `embedder`) into `Retrieval::ContextSynthesizer`.
3. **Retrieval** — `Ports::Retriever#retrieve` receives a `RetrievalQuery` carrying the `RetrievalFilters`. `PgHybridRetriever#retrieve` computes `candidate_limit = query.limit * 3`, runs semantic and keyword searches, applies `ClauseFilters.apply` to both arms, RRF-merges, takes top `limit`, and maps to `RetrievalResult` rows with inlined scalars.
4. **Citation partition** — `ContextSynthesizer#partition_citable` splits the ranked rows into citable and excluded sets using the trust rules above, generating a data-quality preamble when exclusions occur.
5. **Synthesis** — The citable subset is formatted into a numbered evidence block and passed to the LLM synthesizer; citations are mapped back to `clause_id`s.

Sources: `lib/sfl/api/context.rb` `lib/sfl/store/pg_hybrid_retriever.rb` `lib/sfl/retrieval/context_synthesizer.rb`

## Test Coverage and Verification

The retrieval slice is verified by golden-master and unit specs. Notable test files include:

- `spec/store/pg_hybrid_retriever_spec.rb` — verifies RRF merging, filter application timing (F8), candidate limits, and the degraded semantic arm when the embedder returns an empty vector.
- `spec/core/types/retrieval_query_spec.rb`, `spec/core/types/retrieval_filters_spec.rb`, `spec/core/types/classification_metadata_spec.rb` — verify `RetrievalFilters` type construction, unknown-key rejection, enum validation, and optionality.
- `spec/core/pipeline_spec.rb`, `spec/llm/classifier_spec.rb`, `spec/llm/engine_spec.rb` — verify the pipeline passing filters down to retrieval and the downstream context synthesizer.
- `spec/api/clause_review_service_spec.rb`, `spec/gui/review_queue_view_model_spec.rb` — verify the review-queue and UI surfaces consume the same scalar filter types.

The golden master files (`spec/fixtures/golden_master/`) and the legacy baseline (`bench/results/legacy-baseline-conversation.yml`) provide end-to-end verification that the new scalar filter pipeline produces equivalent evidence lists for fixed filter inputs.

Sources: `spec/store/pg_hybrid_retriever_spec.rb` `spec/core/types/retrieval_filters_spec.rb` `spec/core/types/retrieval_query_spec.rb` `spec/core/pipeline_spec.rb` `spec/llm/classifier_spec.rb` `spec/llm/engine_spec.rb` `spec/api/clause_review_service_spec.rb` `spec/gui/review_queue_view_model_spec.rb` `spec/fixtures/golden_master` `bench/results/legacy-baseline-conversation.yml`

## Conceptual Anchors

- **Scalar metafunction** — In SFL, "modality", "mood", and "tenor" are interpersonal metafunction scalars expressed as degree/weight values; "process_type" is an ideational scalar for transitivity. The filters bind these to typed Ruby enums.
- **Source_type (provenance)** — A free-form tag on `clauses` (`"chat_native"`, `"vault_markdown"`, `"api"`, ...) that exists to filter and inspect the origin of a clause.
- **Trusted annotation sources** — Only `"llm"` and `"human"` are trusted for grounding answers and quality scoring; `"fallback"`, `"stub"`, and `"chunk_artifact"` are compiler-substituted defaults that must never silently ground a synthesized answer.
- **F8 fix** — Applying filters before the `limit * 3` fetch, not after the RRF merge; this is the correctness correction vs the legacy retriever.

Sources: `lib/sfl/core/types/retrieval_filters.rb` `lib/sfl/core/types/trusted_annotation_sources.rb` `lib/sfl/store/pg_hybrid_retriever.rb` `lib/sfl/store/clause_filters.rb` `lib/sfl/retrieval/context_synthesizer.rb` `lib/sfl/api/context.rb`

## Next Section: Postgres Integration

Scalar stance filters are the typed frontend to the Postgres-backed hybrid retriever. The next page, `[Postgres Integration](postgres-integration)`, covers the `Sequel` schema (clauses, ideational_payloads, interpersonal_payloads, embeddings, review_queue), the `ON DELETE CASCADE` relationships, the pgvector `embedding` column, and how `PgHybridRetriever` materializes the join scopes (`joined_from_embeddings`, `joined_from_clauses`) that feed the scalar filter application.