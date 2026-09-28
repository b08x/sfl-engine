SFL Engine persists all compiled linguistic data to a single Postgres 16 instance (pgvector-enabled). This page documents the storage layer: the connection manager, the schema built by 11 Sequel migrations, and the five Postgres-backed repository/adapter classes that the pipeline, retrieval, and API layers depend on. The architecture follows a **ports-and-adapters** pattern (see [Ports and Adapters Pattern](ports-and-adapters-pattern)): `Core::Ports` define the contracts, `Store::*` implement them against Postgres, and the API/CLI wire builders inject the concrete implementations.

## Database Connection Layer

The `SFL::Store::Database` module is the single connection manager. It does not run migrations (that is an explicit `rake db:migrate` step in the Rakefile); it only connects and configures the Sequel extension set.

Key configuration decisions:

| Setting | Value | Reason |
|---|---|---|
| `pool_class` | `:timed_queue` | Sequel pool class; combined with `fiber_concurrency` so that Falcon's fiber-based concurrency resolves connections correctly per fiber, not per thread |
| `db.timezone` | `:utc` | Postgres stores `timestamp without time zone` as naive wall-clock values; pinning both the DB and Sequel application timezone to UTC prevents silent round-trip shifts |
| `Sequel.extension :fiber_concurrency` | loaded at module load | Required for correctness under a fiber server even though Falcon is not yet in the Gemfile |
| `pg_json` extension | enabled on connect | Supports `Sequel.pg_jsonb()` for jsonb payload columns |
| `vector` extension | `CREATE EXTENSION IF NOT EXISTS` | Enables pgvector HNSW indexes; also loads `pg_trgm` for the keyword search arm |
| `pg_trgm` extension | `CREATE EXTENSION IF NOT EXISTS` | Enables Postgres full-text search used by the keyword search arm |

The connection URL defaults to `ENV["DATABASE_URL"]`, which in the Docker Compose dev setup points to `postgresql://sfl:sfl@localhost:5433/sfl_engine_dev` (host port 5433, not the system Postgres's 5432, to avoid an ident-auth conflict).

Sources: `lib/sfl/store/database.rb` `docker-compose.yml` `Rakefile`

## Schema Overview

Eleven Sequel migrations (in `db/migrations/`) build the full schema. The schema is written as a set of tables with **real foreign keys** (D5 fix from legacy), **jsonb payloads** for structured metafunction data, and **pgvector HNSW indexes** for semantic search.

**Table: Core Clauses Table**

Sources: `db/migrations/001_create_clauses.rb` `db/migrations/002_create_ideational_payloads.rb` `db/migrations/003_create_interpersonal_payloads.rb` `db/migrations/004_create_embeddings.rb` `db/migrations/005_add_source_type_to_clauses.rb` `db/migrations/008_add_embedding_status_to_clauses.rb` `db/migrations/011_add_parent_clause_id_to_clauses.rb`

**Table: Review & Ingest Tables**

| Table | Purpose | Key FK | Notes |
|---|---|---|---|
| `annotation_reviews` | Append-only audit trail of human Pass 2 review decisions (accepted/rejected/re_annotated) | none (plain `clause_id` string) | Deliberately no FK — deleting a clause should not erase historical review records |
| `review_queue` | Pre-trust content-review queue (image/text/audio items pending review) | none | Status: `pending` → `approved`/`edited`/`rejected` |
| `ingest_review_entries` | Ingest-discipline queue (low-confidence / loader_drafted / draft_failed) | none | Mirrors `review_queue` shape deliberately |

Sources: `db/migrations/006_create_annotation_reviews.rb` `db/migrations/007_create_review_queue.rb` `db/migrations/009_create_ingest_review_entries.rb`

## Repository Layer

There are five concrete Postgres repositories, each implementing a `Core::Ports` contract:

**Diagram: Postgres Repository Layer**

Sources: `lib/sfl/store/pg_clause_store.rb` `lib/sfl/store/pg_embedding_store.rb` `lib/sfl/store/pg_hybrid_retriever.rb` `lib/sfl/store/pg_graph_repository.rb`

### PgClauseStore

The primary write/read adapter for `AnnotatedClause` data. It feeds the pipeline via `#replace_document` and serves the API's `GET /clauses` endpoint via `#find_all`.

- **Write path**: `#replace_document(document_id, clauses)` runs a single transaction — `DELETE` all existing `clauses` rows for the document, then bulk-inserts the new set. The `ideational_payloads` / `interpersonal_payloads` tables use `ON DELETE CASCADE` from `clauses.external_id`, so payload rows are automatically removed by the single `DELETE`. No manual multi-table delete is needed.
- **Idempotency** (F7): the delete-then-insert contract guarantees a re-compile never leaves stale rows.
- **Reconstruct**: jsonb columns (`tokens`, `groups`, `participants`, `circumstances`, `raw_transitivity`, `reasoning_trace`) come back from Postgres with `String` keys and Sequel `JSONBArray`/`JSONBHash` wrappers. `reconstruct_*` methods normalize these to plain Ruby `Hash`/`Array` before passing to `Dry::Struct` because Dry::Types' strict `Array()`/`Hash()` coercions reject non-`instance_of?` wrappers.
- **Ancestor chain**: `#ancestor_chain(external_id)` uses a single `WITH RECURSIVE` SQL round trip walking `parent_clause_id` up the chain. Returns strict ancestors (excludes the given clause) in root-first order.
- **Self-referential FK**: `clauses.parent_clause_id → clauses.external_id` with `ON DELETE CASCADE` plus a CHECK constraint (`parent_clause_id IS NULL OR parent_clause_id <> external_id`) and a `BEFORE INSERT OR UPDATE` PL/pgSQL trigger that prevents cycles (A→B→A).

Sources: `lib/sfl/store/pg_clause_store.rb`

### PgEmbeddingStore

The `Core::Ports::EmbeddingStore` implementation backed by `embeddings` with a `vector(768)` column (`vector(768)` is fixed at migration time; the `PgEmbeddingStore::VECTOR_DIMENSIONS = 768` constant must match the column width, otherwise a mismatched model (e.g. a 1024-dim Mistral embed) surfaces deep inside `Sequel#multi_insert` as `PG::DataException`).

Key behaviors:

- `#replace_document` deletes all `embeddings` rows for the document's clause_ids *and* updates `clauses.embedding_status` for every clause in the document — embedded, failed, or not — inside one transaction. A nil/empty vector for a clause_id means that clause's embed attempt failed; the clause is marked `embedding_status = "failed"` with an `embedding_error` note rather than writing a degenerate empty vector that would look like a real row to downstream cosine search.
- The `embeddings` table carries a composite unique index on `(clause_id, model)`, so vectors from multiple models (e.g. Ollama `embeddinggemma:latest` 768-dim vs Mistral 1024-dim) can coexist for the same clause.
- F11: `embedding_status` column defaults `"pending"` at the DB level; `embedding_error` carries failure reasons. The `EmbeddingRedriver` re-drives pending/failed clauses in document batches, merging existing good vectors with newly re-driven ones before calling `#replace_document` (data-loss guard: a narrow "update these clause_ids" call on a document would otherwise delete already-good vectors).

Sources: `lib/sfl/store/pg_embedding_store.rb`

### PgHybridRetriever

The `Core::Ports::Retriever` implementation combining two search arms, merged with **Reciprocal Rank Fusion (RRF)** using the standard constant `RRF_K = 60`:

1. **Semantic arm**: pgvector cosine similarity via `embedding <=> ?` (HNSW index with `vector_cosine_ops`). If the embedder returns an empty vector (e.g. Null::Embedder), the arm returns `[]` instead of sending a malformed `<=>` comparison to Postgres.
2. **Keyword arm**: Postgres full-text search with `to_tsvector('simple', text) @@ plainto_tsquery('simple', query)`, ordered by `ts_rank(...) DESC`.

**F8 fix vs legacy**: legacy ran both arms unfiltered at `limit * 3`, RRF-merged, then filtered, then took `.first(limit)` — a selective filter could starve the result. Here, `ClauseFilters.apply` pushes every `RetrievalFilters` attribute into the `SQL .where(...)` of **both** arms *before* `.order`/`.limit`. The `limit * 3` candidate pool per arm is already filter-matching.

Both arms join `clauses` → `interpersonal_payloads` → `ideational_payloads` so that scalar-filter attributes (mood, tenor, modality_weight, process_type) ride along for free. The RRF merge itself stays in Ruby over at most `2 * (limit * 3)` rows.

Sources: `lib/sfl/store/pg_hybrid_retriever.rb` `lib/sfl/store/clause_filters.rb`

### PgGraphRepository

Read-only graph view over `clauses`/`embeddings` for `GET /graph/nodes` and `GET /graph/edges`:

- `nodes(document_id:)` returns clause nodes with mood, tenor, process_type, and readability columns.
- `parent_child_edges(document_id:)` returns self-referential parent/child edges (`parent_clause_id` is `NULL` for root clauses).
- `semantic_neighbors(clause_id, k:, min_similarity:)` reuses the pgvector cosine-distance pattern scoped to a single seed clause, returning edges with a `similarity` weight.

Sources: `lib/sfl/store/pg_graph_repository.rb`

### Review & Ingest Repositories

Three additional Postgres repositories (not `Core::Ports` adapters — no second consumer needs a swappable backend):

| Class | Table | Key behaviors |
|---|---|---|
| `PgReviewQueueRepository` | `review_queue` | `enqueue`, `find`, `pending(modality:, limit:, offset:)`, `decide(id:, decision:, ...)`. Decision coerced to a `STATUS_FOR_DECISION` mapping (`approve`→`approved`, `edit`→`edited`, `reject`→`rejected`). The `content_type`/`source_type` parameters are safely coerced with `&.to_s` because Sequel renders a bare Symbol as an unquoted SQL identifier (live-verified `PG::UndefinedColumn` in legacy). |
| `PgAnnotationReviewRepository` | `annotation_reviews` | `record_review`, `reviews_for`, `review_queue(limit:, offset:)`. The `review_queue` query excludes already-accepted clauses (otherwise "Accept" would loop forever because "Accept" intentionally leaves `annotation_source` untouched). Deliberately no FK to `clauses` since this is an append-only audit trail. |
| `PgIngestReviewRepository` | `ingest_review_entries` | `enqueue`, `find`, `resolved?(path)`. Mirrors `PgReviewQueueRepository` shape for future UI/CLI parity. |

Sources: `lib/sfl/store/pg_review_queue_repository.rb` `lib/sfl/store/pg_annotation_review_repository.rb` `lib/sfl/store/pg_ingest_review_repository.rb`

## Connection Wiring

The connection is established in two contexts:

1. **CLI / Boot** — `SFL::Boot#connect_db` reads `DATABASE_URL`, calls `SFL::Store::Database.connect(url)`, and calls `SFL::Store::Database.setup_extensions(db)`. The resulting `Sequel::Database` is stored in `Boot::Result#db` and passed to `API::Context.build`.
2. **Roda / config.ru** — `Providers::DB::Conn.boot` calls `SFL::Store::Database.connect(Config.get[:db][:url])` and `SFL::Store::Database.setup_extensions(@conn)`, then sets the connection on `DB` (a module constant used by routes). `SFL::Boot` is called with `require_db: false` because the Roda-managed `DB` is already connected.

`API::Context.build` wires the concrete implementations:

- `clause_store: Store::PgClauseStore.new(boot_result.db)`
- `retriever: Store::PgHybridRetriever.new(db: boot_result.db, embedder: boot_result.embedder)`
- `synthesizer: Retrieval::ContextSynthesizer.new(..., retriever: Store::PgHybridRetriever.new(...), ...)`
- `review_queue_repo: Store::PgReviewQueueRepository.new(boot_result.db)`
- `annotation_review_repo: Store::PgAnnotationReviewRepository.new(boot_result.db)`
- `graph_repository: Store::PgGraphRepository.new(db: boot_result.db)`

Sources: `lib/sfl/api/context.rb` `app/config/providers/db/conn.rb` `lib/sfl/boot.rb`

## Test Database Isolation

Specs use a dedicated, isolated database: `postgresql://sfl:sfl@localhost:5433/sfl_engine_v2_test` (from the Docker Compose `init-test-db.sql` and `spec/support/store_test_db.rb`).

- `StoreTestDb.db` connects to the test database and runs all 11 migrations on first access.
- `StoreTestDb.clean!` runs a `TRUNCATE ... RESTART IDENTITY CASCADE` across all seven store tables before every example, so specs never touch real data from an interactive/manual run against `sfl_engine_dev`.
- The test spec for `PgEmbeddingStore` cannot use the shared "embedding store port" example because `Fake::EmbeddingStore` writes 2-dimensional vectors, while `embeddings.embedding` is a fixed `vector(768)` — Postgres itself would reject a dimension mismatch, which the fake cannot reproduce. The behavior is instead covered by explicit examples in `pg_embedding_store_spec.rb`.

Sources: `spec/support/store_test_db.rb` `spec/store/pg_embedding_store_spec.rb` `docker/init-test-db.sql`

## Schema-to-Application Mapping

**Diagram: Postgres Schema → Ruby Types**

Sources: `lib/sfl/store/pg_clause_store.rb` `lib/sfl/core/types/annotated_clause.rb` `lib/sfl/core/types/syntactic_clause.rb` `lib/sfl/core/types/ideational_payload.rb` `lib/sfl/core/types/interpersonal_payload.rb` `db/migrations/001_create_clauses.rb`

## Key Deployment Configuration

| Environment variable | Default | Purpose |
|---|---|---|
| `DATABASE_URL` | `postgresql://sfl:sfl@localhost:5433/sfl_engine_dev` | Connection string (Docker Compose dev); `sfl_engine_v2_test` for specs |
| `EMBEDDING_MODEL` | `embeddinggemma:latest` | Model identifier stored per row; must match `vector(768)` column width |
| `SFL_TASK_EMBEDDING_PROVIDER` / `SFL_TASK_EMBEDDING_MODEL` | ollama / embeddinggemma:latest | Embedding provider (any provider returning a 768-dim vector) |
| `SFL_API_CORS_ORIGINS` | unset | Comma-separated allowed origins for `OPTIONS /preflight` |

The Docker Compose `postgres` service uses `image: pgvector/pgvector:0.8.6-pg16` with `ports: - "127.0.0.1:5433:5232"` (host port 5433, not the system Postgres's 5432).