The Interpersonal Payload is the data structure that carries the **interpersonal metafunction** of a clause — how language is used to enact social relationships, express commitment, and position speakers relative to their audience. It is produced by Pass 2 of the two-pass pipeline as the LLM's annotation output, shaped into a typed `Dry::Struct` before being persisted to Postgres and consumed by retrieval, aggregation, and review workflows.

This page explains the Interpersonal Payload: its type definition, database schema, the pipeline stages that produce and consume it, and how it is used across the system.

Sources: [lib/sfl/core/types/interpersonal_payload.rb#L1-L23](lib/sfl/core/types/interpersonal_payload.rb#1-23), [db/migrations/003_create_interpersonal_payloads.rb#L1-L34](db/migrations/003_create_interpersonal_payloads.rb#1-34), [lib/sfl/core/pipeline.rb#L1-L265](lib/sfl/core/pipeline.rb#1-265)

## What the Interpersonal Payload Contains

The Interpersonal Payload is a `Dry::Struct` subclass with eight core attributes. Every field is mapped to both an in-memory struct and a persisted database row, keeping the two representations in lockstep.

| Attribute | Type | DB Column | Notes |
|-----------|------|-----------|-------|
| `clause_id` | `String` | `clause_id` (FK) | The outer AnnotatedClause id; referenced by `clauses.external_id` with `ON DELETE CASCADE` |
| `mood` | `MoodType` (enum) | `mood` | canonical SFL mood: declarative, interrogative, imperative, exclamative, indicative, minor, fragment |
| `modality_weight` | `Float 0.0–1.0` | `modality_weight` | certainty: 0 = hedged/weak, 1 = strong/certain; coercible (bare `0`/`1` accepted) |
| `tenor` | `Float 0.0–1.0` | `tenor` | formality 0 = informal, 1 = formal; coercible (bare `0`/`1` accepted) |
| `speaker_attitude` | `String` (optional) | `speaker_attitude` | e.g. neutral, positive, negative, skeptical, assertive |
| `reasoning` | `String` (optional) | `reasoning` | step-by-step explanation of the classification |
| `annotation_source` | `AnnotationSource` (enum) | `annotation_source` | `llm`, `fallback`, `stub`, `chunk_artifact`, `human` |
| `reasoning_trace` | `ReasoningTrace` (optional) | `reasoning_trace` | structured derivation: premises, inference rule, conclusion, confidence, derivation hash |

Sources: [lib/sfl/core/types/interpersonal_payload.rb#L1-L23](lib/sfl/core/types/interpersonal_payload.rb#1-23), [db/migrations/003_create_interpersonal_payloads.rb#L1-L34](db/migrations/003_create_interpersonal_payloads.rb#1-34)

### Mood and threshold types

Mood is constrained by `MoodType = String.enum(...)` for the seven canonical SFL moods, with aliases handled by `ClassificationRegistry.normalize`. Modality weight and tenor are both `Coercible::Float.constrained(gteq: 0.0, lteq: 1.0)`, so an LLM emitting `0`/`1` as bare JSON integers does not fail the whole annotation.

Sources: [lib/sfl/core/types/mood_type.rb#L1-L13](lib/sfl/core/types/mood_type.rb#1-13), [lib/sfl/core/types/modality_weight.rb#L1-L5](lib/sfl/core/types/modality_weight.rb#1-5), [lib/sfl/core/types/tenor_value.rb#L1-L5](lib/sfl/core/types/tenor_value.rb#1-5), [lib/sfl/core/classification_registry.rb#L30-L65](lib/sfl/core/classification_registry.rb#30-65)

### Provenance & trust

`annotation_source` is the single source of truth for whether a value came from the compiler. `TRUSTED_ANNOTATION_SOURCES = %w[llm human]` defines which sources are trusted for grounding answers, quality scoring, and "needs attention" predicates. `fallback`, `stub`, and `chunk_artifact` are compiler-substituted defaults, never trusted.

Sources: [lib/sfl/core/types/trusted_annotation_sources.rb#L1-L16](lib/sfl/core/types/trusted_annotation_sources.rb#1-16), [lib/sfl/core/types/annotation_source.rb#L1-L18](lib/sfl/core/types/annotation_source.rb#1-18)

## Database Schema

The `interpersonal_payloads` table is created by migration `db/migrations/003_create_interpersonal_payloads.rb` and shares the same real-FK treatment as `ideational_payloads` (D5). Like its ideational twin, it conditions on `clauses.external_id` via `ON DELETE CASCADE`, so dropping a clause's rows in `clauses` automatically removes the payload rows.

| Column | Type | Constraints |
|--------|------|-------------|
| `id` | primary key | |
| `clause_id` | String | FK → `clauses.external_id`, `null: false`, `on_delete: cascade`, unique index |
| `mood` | String | `null: false` |
| `modality_weight` | Float | `null: false`, default `0.5` |
| `tenor` | Float | `null: false`, default `0.5` |
| `speaker_attitude` | String | nullable |
| `reasoning` | String | nullable |
| `annotation_source` | String | `null: false`, default `"llm"` |
| `reasoning_trace` | jsonb | nullable |
| `created_at` | DateTime | `null: false`, default `CURRENT_TIMESTAMP` |
| `raw_classification` | String | not in migration (pass-2 metadata) |
| `classification_status` | String | not in migration (pass-2 metadata) |
| `untrusted` | Boolean | not in migration (computed flag) |

Indexes: `clause_id` (unique), `modality_weight`, `tenor`, `mood`, plus a composite index `idx_interpersonal_scalar_filter` on `[mood, modality_weight, tenor]` for retrieval scalar-filter + ranking queries.

Sources: [db/migrations/003_create_interpersonal_payloads.rb#L1-L34](db/migrations/003_create_interpersonal_payloads.rb#1-34)

### Relationship to clauses

The payload table is joined to clauses two ways:

1. **Pipeline → Store**: `Pipeline#build_annotated_clause` produces each `AnnotatedClause` with both `id` and an `interpersonal` payload; `PgClauseStore#insert_all` maps `interpersonal` to the `interpersonal_payloads` rows via `clause_id: clause.id` (which equals `clauses.external_id`).
2. **Consumer → DB**: `PgHybridRetriever`, `PgClauseStore#find_all`, and `PgAnnotationReviewRepository#review_queue` all join `interpersonal_payloads` to `clauses` on `clause_id`. The ambiguity between `clauses.external_id` and `interpersonal_payloads.clause_id` is resolved explicitly with `Sequel[:clauses][:external_id]`.

Sources: [lib/sfl/core/pipeline.rb#L185-L201](lib/sfl/core/pipeline.rb#185-201), [lib/sfl/store/pg_clause_store.rb#L147-L161](lib/sfl/store/pg_clause_store.rb#147-161), [lib/sfl/store/pg_hybrid_retriever.rb#L85-L96](lib/sfl/store/pg_hybrid_retriever.rb#85-96)

## Where the Interpersonal Payload Comes From

Pass 2 (the `Ports::Annotator` port) owns the production of `InterpersonalPayload`. Two implementations matter.

### Pipeline path (full two-pass compile)

The `Pipeline` class composes Pass 1 (SyntacticParser + IdeationalExtractor) with Pass 2 (an `Annotator`). The relevant stages are:

```
Pipeline#compile
  └─ parse (Pass 1)
  └─ pair_with_ideational (clause → ideational)
  └─ annotate
       ├─ stub_annotate_all  (pass_one_only=true → Ports::Null::Annotator)
       ├─ annotate_all (pass_two.annotate_batch)
       └─ annotate_with_cache (resume + document_id)
  └─ persist (PgClauseStore#replace_document)
  └─ embed_all
```

`build_annotated_clause` constructs the `InterpersonalPayload` from the `AnnotationResult`:

Sources: [lib/sfl/core/pipeline.rb#L84-L99](lib/sfl/core/pipeline.rb#84-99), [lib/sfl/core/pipeline.rb#L185-L201](lib/sfl/core/pipeline.rb#185-201)

### The stub / fallback paths

The pipeline has three ways a clause can end up with Interpersonal values that are NOT real LLM output:

1. **`--pass1-only` mode** → `stub_annotate_all` calls `Ports::Null::Annotator`, which produces `mood: "declarative"`, `modality_weight: 0.5`, `tenor: 0.5`, `annotation_source: "stub"`.
2. **Degradation** → LLM engine emits defaults `annotation_source: "fallback"` when a response is malformed or a contract violation occurs (via `LLM::Degradation.default_interpersonal`).
3. **Cache poisoning / chunk artifacts** → `Analysis::Engine` marks a clause `annotation_source: "chunk_artifact"` when it was affected by a chunk-split boundary default rather than a real annotation.

All three paths set `annotation_source` correctly, which is what `TRUSTED_ANNOTATION_SOURCES` and the review queue rely on.

Sources: [lib/sfl/core/pipeline.rb#L124-L132](lib/sfl/core/pipeline.rb#124-132), [lib/sfl/core/ports/null/annotator.rb#L1-L49](lib/sfl/core/ports/null/annotator.rb#1-49), [lib/sfl/llm/degradation.rb#L1-L41](lib/sfl/llm/degradation.rb#1-41), [lib/sfl/analysis/engine.rb#L181-L191](lib/sfl/analysis/engine.rb#181-191)

## Consumption Map

The Interpersonal Payload flows outward through several consumption points:

- **`AnnotationResult`/`AnnotatedClause`**: the typed struct carrying `interpersonal` (required) and optional `textual`. `AnnotatedClause` is the full two-pass compiler output.
- **`PgClauseStore#replace_document`**: bulk-inserts `interpersonal_payloads` rows; `reconstruct_interpersonal` reads them back into `InterpersonalPayload` structs for `@db[:clauses]` scans and reconstruction.
- **`PgClauseStore#update_interpersonal`**: single-clause re-annotation write path (HITL "re_annotated" review decision re-runs Pass 2 only, without touching clauses or ideational_payloads rows).
- **`PgHybridRetriever`**: joins `interpersonal_payloads` to `clauses` in both semantic and keyword search arms to push `RetrievalFilters` into SQL, then inlines `mood`, `tenor`, `modality_weight`, `annotation_source`, `untrusted`, `process_type` onto each `RetrievalResult`.
- **`Analysis::Engine`**: aggregates `avg_tenor`, `avg_modality`, `dominant_mood`, `mood_counts`, and `annotation_source == "chunk_artifact"` marking over the Interpersonal Payload across turns and conversation-level results.
- **CLI / API**: `--mood`, `--min-tenor`, `--max-tenor`, `--min-modality`, `--max-modality` options on `sfl-analyze context` map to `RetrievalFilters` that `PgHybridRetriever` applies.

Sources: [lib/sfl/core/types/annotated_clause.rb#L1-L21](lib/sfl/core/types/annotated_clause.rb#1-21), [lib/sfl/core/types/annotation_result.rb#L1-L16](lib/sfl/core/types/annotation_result.rb#1-16), [lib/sfl/store/pg_clause_store.rb#L32-L65](lib/sfl/store/pg_clause_store.rb#32-65), [lib/sfl/store/pg_hybrid_retriever.rb#L1-L163](lib/sfl/store/pg_hybrid_retriever.rb#1-163), [lib/sfl/analysis/engine.rb#L178-L191](lib/sfl/analysis/engine.rb#178-191), [lib/sfl/cli.rb#L182-L195](lib/sfl/cli.rb#L182-195)

### The retrieval scalar filter slice

The retrieval slice's scalar filters (`mood`, `modality_weight`, `tenor`) are applied to the `interpersonal_payloads` table:

| Filter | Column | Predicate |
|-------|--------|-----------|
| `mood` | `interpersonal_payloads.mood` | equality |
| `min_modality` | `interpersonal_payloads.modality_weight` | `>=` |
| `max_modality` | `interpersonal_payloads.modality_weight` | `<=` |
| `min_tenor` | `interpersonal_payloads.tenor` | `>=` |
| `max_tenor` | `interpersonal_payloads.tenor` | `<=` |

The composite index on `[mood, modality_weight, tenor]` exists specifically to serve these scalar-filter + ranking queries.

Sources: [lib/sfl/store/clause_filters.rb#L1-L44](lib/sfl/store/clause_filters.rb#1-44)

### The HITL review queue

`PgAnnotationReviewRepository#review_queue` uses `interpersonal_payloads.annotation_source` to find clauses that "need attention" — those whose annotation source is not in `TRUSTED_ANNOTATION_SOURCES`. It excludes clauses a human has already accepted (via `annotation_reviews.decision = "accepted"`), so that "Accept" actually clears the queue.

Sources: [lib/sfl/store/pg_annotation_review_repository.rb#L87-L113](lib/sfl/store/pg_annotation_review_repository.rb#87-113)

## The Two-Pass Pipeline in Context

The Interpersonal Payload is one half of the two-pass compilation contract. Pass 1 produces the Ideational metafunction (process type, participants, circumstances); Pass 2 produces both the Ideational (signed) and Interpersonal payloads. Together with Textual, this is the full SFL metafunction decomposition.

Sources: [lib/sfl/core/pipeline.rb#L10-L17](lib/sfl/core/pipeline.rb#10-17)

## What Changes When You Re-Analyze

`update_interpersonal` in `PgClauseStore` is the single-clause re-annotation path. It updates only the `interpersonal_payloads` row, explicitly leaving `clauses` and `ideational_payloads` untouched so syntactic structure, `process_type`, and `participants` survive a human-in-the-loop re-run.

Sources: [lib/sfl/store/pg_clause_store.rb#L51-L65](lib/sfl/store/pg_clause_store.rb#51-65)

## Key Design Decisions

**D5 — real FKs.** Migration 003 uses a real foreign key on `clauses.external_id` with `ON DELETE CASCADE`, rather than relying on row-level semantics. This means payload rows cannot be manually deleted without removing the clause, and the two-table relationship is enforced by Postgres.

**Reasoning trace as first-class data.** Unlike the legacy migration that backfilled via `add_column`, `reasoning_trace` is defined directly in `create_table` as a nullable `jsonb` column. The `reasoning_trace` value is a `ReasoningTrace` struct (premises, inference_rule, conclusion, confidence, derivation_hash, generated_at), persisted via `Sequel.pg_jsonb(Core::Wire.dump(...))` and read back via `reconstruct_reasoning_trace`.

Sources: [db/migrations/003_create_interpersonal_payloads.rb#L3-L7](db/migrations/003_create_interpersonal_payloads.rb#3-7), [lib/sfl/store/pg_clause_store.rb#L212-L236](lib/sfl/store/pg_clause_store.rb#212-236)

**`clause_id` is a distinct uuid, collapsed at write time.** `AnnotatedClause#id` (the outer id) is written to `interpersonal_payloads.clause_id` and `clauses.external_id`. The upstream `SyntacticClause#id`, `IdeationalPayload#clause_id`, and `InterpersonalPayload#clause_id` are distinct uuids; the store collapses them all to the outer annotated id — an accepted lossy round trip.

Sources: [lib/sfl/store/pg_clause_store.rb#L20-L27](lib/sfl/store/pg_clause_store.rb#20-27)

**No `clauses.interpersonal` column.** The payload lives in its own table, one row per clause. `interpersonal_payloads.clause_id` is the unique join key.

**`mood` values are canonical.** `MoodType` constrains to the seven `ClassificationRegistry.canonical` values. LLM output is normalized through `ClassificationRegistry.normalize`, with `classification_status` (`exact`/`aliased`/`fuzzy`/`unknown`) logged and surfaced as `untrusted` when the value fell to the default (`:unknown`).

Sources: [lib/sfl/core/types/mood_type.rb#L1-L13](lib/sfl/core/types/mood_type.rb#1-13), [lib/sfl/llm/engine.rb#L255-L277](lib/sfl/llm/engine.rb#255-277)

## Type Relationships

The Interpersonal Payload does not exist in isolation. It is consumed by and references these types:

Sources: [lib/sfl/core/types/interpersonal_payload.rb#L1-L23](lib/sfl/core/types/interpersonal_payload.rb#1-23), [lib/sfl/core/types/annotated_clause.rb#L1-L21](lib/sfl/core/types/annotated_clause.rb#1-21), [lib/sfl/core/types/annotation_result.rb#L1-L16](lib/sfl/core/types/annotation_result.rb#1-16), [lib/sfl/core/types/classification_status.rb#L1-L5](lib/sfl/core/types/classification_status.rb#1-5), [lib/sfl/store/pg_clause_store.rb#L195-L211](lib/sfl/store/pg_clause_store.rb#L195-211)

### The three scalar dimensions at a glance

Sources: [lib/sfl/core/types/interpersonal_payload.rb#L9-L16](lib/sfl/core/types/interpersonal_payload.rb#9-16), [lib/sfl/core/types/mood_type.rb#L1-L13](lib/sfl/core/types/mood_type.rb#1-13)

## Where to Go Next

- The Interpersonal Payload's sibling table, **Ideational Payload**, carries the process type, participants, and circumstances of the same clause. See [Ideational Payload](ideational-payload).
- The **Database Schema** page documents all payload tables and their indexes. See [Database Schema](database-schema).
- **Two-Pass Pipeline Architecture** explains how Pass 1 and Pass 2 compose into `Pipeline#compile`. See [Two-Pass Pipeline Architecture](two-pass-pipeline-architecture).
- **Hexagonal Architecture Pattern** shows how `Ports::Annotator` and `Ports::ClauseStore` decouple the domain from the LLM and database. See [Hexagonal Architecture Pattern](hexagonal-architecture-pattern).
- **Hybrid Retrieval with RRF** shows how `RetrievalFilters` (from `interpersonal_payloads`) are applied in both search arms. See [Hybrid Retrieval with RRF](hybrid-retrieval-with-rrf).
- **Review Queues** documents the HITL flow that uses `annotation_source` to find clauses needing attention. See [Review Queues](review-queues).