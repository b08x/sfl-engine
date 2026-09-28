The content-review queue is the safety net that sits between **raw, unverified AI output** and **permanently stored linguistic data**. It exists in three places — a Postgres-first content-review queue for vision/text/audio extractions, a parallel ingest-review table for unclassifiable files, and a clause-level annotation audit trail — and four consumer paths: an HTTP API, a Ruby desktop GUI, the knowledge-base compiler, and the ingest orchestrator. This page focuses on how the content-review queue (Postgres table `review_queue`) is designed, who writes to it, who reads from it, how decisions mutate stored data, and how the GUI keeps a human reviewer in the loop.

Sources: [./db/migrations/007_create_review_queue.rb](db/migrations/007_create_review_queue.rb), [./lib/sfl/store/pg_review_queue_repository.rb](lib/sfl/store/pg_review_queue_repository.rb), [./app/routes/review_queue.rb](app/routes/review_queue.rb), [./lib/sfl/api/context.rb](lib/sfl/api/context.rb), [./lib/sfl/gui/review_queue_app.rb](lib/sfl/gui/review_queue_app.rb), [./lib/sfl/analysis/knowledge_base_source.rb](lib/sfl/analysis/knowledge_base_source.rb), [./lib/sfl/ingest/orchestrator.rb](lib/sfl/ingest/orchestrator.rb)

## The Content-Review Queue: What It Tracks

The content-review queue (table `review_queue`) does **not** review annotations that already exist. Migration `006_create_annotation_reviews.rb` makes this explicit: it is an append-only audit trail for Pass 2 annotation *decisions* (confidence, mood/tenor/etc correctness) on text everyone already trusts. The content-review queue instead asks one question before anything is stored: **is the generated text itself trustworthy?** It covers vision-model descriptions of images, low-quality or fallback text extractions, and transcript segments.

The table shape is deliberately parallel to `annotation_reviews`: a UUID primary key, a `status` defaulting to `"pending"`, plus `modality` (`image | text | audio`), `document_id`, `source_file`, `generated_text`, `reason`, `source_type`, `content_type`, `created_at`, and `reviewed_at`.

| Column | Purpose | Notes |
|---|---|---|
| `id` | UUID primary key | Plain-string-key convention, no FK |
| `modality` | `"image" \| "text" \| "audio"` | Null not allowed |
| `document_id` | Stable document key | Target of store replacement on edit/reject |
| `generated_text` | The draft under review | Null not allowed |
| `reason` | Why this was flagged | e.g. `image`, `fallback_annotation`, `low_quality_score`, `audio_transcript` |
| `source_type` | Provenance tag | Restored on edit's recompile |
| `content_type` | Optional type hint | Coerced to String on insert |
| `status` | Lifecycle state | `pending` → `approved`/`edited`/`rejected` |
| `reviewer` | Who decided | Requires `SFL_REVIEWER_NAME` env in the GUI |
| `created_at` / `reviewed_at` | Timestamps | Stored as UTC naive Postgres `timestamp` |

Sources: [./db/migrations/007_create_review_queue.rb](db/migrations/007_create_review_queue.rb), [./db/migrations/006_create_annotation_reviews.rb](db/migrations/006_annotation_reviews.rb), [./lib/sfl/store/pg_review_queue_repository.rb](lib/sfl/store/pg_review_queue_repository.rb)

## Decisions and Status Mapping

`PgReviewQueueRepository` fixes the decision vocabulary in `DECISIONS = Core::Types::ReviewQueueDecision.values`, a `String.enum` of `approve`, `edit`, and `reject`. Each decision maps to a persisted status:

Sources: [./lib/sfl/store/pg_review_queue_repository.rb](lib/sfl/store/pg_review_queue_repository.rb), [./lib/sfl/core/types/review_queue_decision.rb](lib/sfl/core/types/review_queue_decision.rb)

| Decision | Persisted status | Side effects |
|---|---|---|
| `approve` | `approved` | None — review complete, storage untouched |
| `edit` | `edited` | Caller must recompile via `Pipeline#compile`; repository only records the decision |
| `reject` | `rejected` | Caller must clear the document's stored clauses via `Pipeline#replace_document(document_id, [])` |

`PgReviewQueueRepository#decide` is deliberately a *record-only* method: it does not persist `edited_text`. The caller owns the recompile and the store write. It returns `nil` for an unknown id and raises `ArgumentError` on an unrecognized decision. This separation is what lets the API and the GUI both reuse one method without coupling it to the pipeline.

Sources: [./lib/sfl/store/pg_review_queue_repository.rb](lib/sfl/store/pg_review_queue_repository.rb), [./app/routes/review_queue.rb](app/routes/review_queue.rb), [./lib/sfl/core/types/review_queue_decision.rb](lib/sfl/core/types/review_queue_decision.rb)

## Who Builds the Queue, and Who Consumes It

The queue is composed in one place — `SFL::API::Context.build` — and every HTTP consumer pulls from the same collaborator.

Sources: [./lib/sfl/api/context.rb](lib/sfl/api/context.rb)

Sources: [./lib/sfl/api/context.rb](lib/sfl/api/context.rb), [./app/config/providers/engine.rb](app/config/providers/engine.rb), [./app/sfl.rb](app/sfl.rb)

- `SFL::Store::PgReviewQueueRepository` is the Postgres-backed implementation. It is **not** a `Core::Ports` adapter — a second swappable consumer does not exist yet, so the repo is a composition-root class rather than a pluggable port.
- `SFL::Core::Types::ReviewQueueDecision` is the decision vocabulary for this queue, deliberately separate from `ReviewDecision` (`accepted`/`rejected`/`re_annotated`), which belongs to the unrelated annotation-confidence audit flow.
- `Store::PgAnnotationReviewRepository` is the separate clause-level annotation audit trail (migration `006`), consumed by `POST /clauses/:id/review` via `ClauseReviewService` — not by the content-review queue.

Sources: [./lib/sfl/store/pg_review_queue_repository.rb](lib/sfl/store/pg_review_queue_repository.rb), [./lib/sfl/core/types/review_queue_decision.rb](lib/sfl/core/types/review_queue_decision.rb), [./lib/sfl/store/pg_annotation_review_repository.rb](lib/sfl/store/pg_annotation_review_repository.rb), [./spec/store/pg_annotation_review_repository_spec.rb](spec/store/pg_annotation_review_repository_spec.rb)

## HTTP API Surface

`app/routes/review_queue.rb` wires the queue under the `review-queue` hash branch. It is a Roda app, autoloaded from `./app/routes` via `app/sfl.rb`, so `POST /review-queue/decide` resolves as `hash_branch("review-queue") → r.on String(id) → is "decide"`.

| Method / Path | Behavior |
|---|---|
| `GET /review-queue?modality=&limit=&offset=` | Returns `{ items, total }` from `ctx.review_queue_repo.pending(modality:, limit:, offset:)` |
| `POST /review-queue/:id/decide` | Validates `decision` against `ReviewQueueDecision.values`, then calls `apply_review_queue_decision` and `ctx.review_queue_repo.decide(id:, decision:, edited_text:, reviewer:)` |

Request validation is explicit rather than implicit: `decision` must be one of the enum values; `edit` additionally requires `edited_text`. A missing row returns HTTP 404.

`apply_review_queue_decision` is the contract between the queue and the store:

- **approve** — marks the row reviewed and leaves storage untouched.
- **reject** — calls `ctx.clause_store.replace_document(row[:document_id], [])`, deleting the document's stored clauses.
- **edit** — calls `ctx.pipeline.compile(edited_text, document_id:, store:, embed:, resume: false)`. The `.value_or` guard raises on compile failure, so the recompile happens inside a single transaction with the decision recorded.

Sources: [./app/routes/review_queue.rb](app/routes/review_queue.rb), [./lib/sfl/api/context.rb](lib/sfl/api/context.rb), [./lib/sfl/store/pg_clause_store.rb](lib/sfl/store/pg_clause_store.rb)

## The GUI: Reviewer Attribution, Selection, and Stale-Data Safety

`SFL::GUI::ReviewQueueApp` is the composition root for a LibUI desktop window. It uses Glimmer for layout (side-by-side `ItemListControl` and `DetailPaneControl`) and owns a 10-second auto-refresh timer. The app is constructed from **injectable** collaborators — `repo`, `pipeline`, and `logger` — so it can run as a plain Ruby object in spec without a display or a database.

Three invariants govern the GUI:

**1. Reviewer attribution is a hard startup failure.** `SFL_REVIEWER_NAME` must be set and non-blank, otherwise `MissingReviewerNameError` (a subclass of `SFL::Error`) is raised **before** `Boot.call` opens a database or validates an LLM. Every decision row is traced to a person.

**2. `ReviewQueueViewModel` is the only GUI-layer class that touches the repository or the pipeline.** Custom controls bind through it, never directly. Its action methods return `Dry::Monads::Result` (Success/Failure), matching `Pipeline#compile`'s return shape.

**3. Selection and edited text survive refreshes, and mid-compile edits are rejected.** A 10-second auto-refresh can resolve the selected row out from under the reviewer; `sync_selection_after_refresh` preserves selection only while the row is still pending and clears `edited_text` otherwise. Because Glimmer observers notify synchronously, background-compile state mutation is isolated in `compile_for_recompile!` (no Glimmer-mutating writes), and `finish_recompile!` compares a captured `selected_item_id` against the live value — if the reviewer clicked a different row while a compile was in flight, the edit is not recorded and `SELECTION_CHANGED_MESSAGE` is returned.

| Method | Return | Side effects |
|---|---|---|
| `refresh!` | `Success(items)` or `Failure(message)` | Loads `repo.pending(modality: modality_filter_param)`, repairs selection |
| `select_row(index)` / `select(item)` | none | Sets `selected_item`, seeds `edited_text` from `generated_text` |
| `approve!` / `reject!` | `Success` or `Failure` | `repo.decide(id:, decision:, reviewer:)` then `refresh!` |
| `save_and_recompile!` | `Success` or `Failure` | `compile_for_recompile` (worker-safe) → `finish_recompile!` (main-thread only) |
| `compile_for_recompile` | pipeline's `Result` | Mutates nothing |
| `finish_recompile!(compile_result, compiled_item_id:)` | Success or `Failure(SELECTION_CHANGED_MESSAGE)` | Records `edit` decision, refreshes |

The modal decides — `approve`/`reject`/`edit` — all funnel through the private `decide!`, which also rescues `StandardError` and logs, never raising, so a DB outage cannot unwind the LibUI event loop.

Sources: [./lib/sfl/gui/review_queue_app.rb](lib/sfl/gui/review_queue_app.rb), [./lib/sfl/gui/review_queue_view_model.rb](lib/sfl/gui/review_queue_view_model.rb), [spec/gui/review_queue_app_spec.rb](spec/gui/review_queue_app_spec.rb), [spec/gui/review_queue_view_model_spec.rb](spec/gui/review_queue_view_model_spec.rb)

## Who Writes to the Queue at the Source

### Knowledge-Base Compiler

`SFL::Analysis::KnowledgeBaseSource#compile_artifact` is the second writer. After `Pipeline#compile` yields clauses, it classifies the content type (`ContentTypeClassifier`) and scores quality (`QualityScorer`); a clause with a non-trusted `annotation_source` (anything outside `TRUSTED_ANNOTATION_SOURCES`), or an artifact below `LOW_QUALITY_THRESHOLD` (0.40), triggers `enqueue_review`. Image artifacts are always enqueued with `modality: image` and `reason: image`; text artifacts are enqueued with `reason: fallback_annotation` or `reason: low_quality_score`.

This is how the queue is populated at ingest time: the knowledge-base compiler walks `.md`/`.canvas`/`.pdf`/image units, compiles each into clauses, and writes each reviewable artifact to the same `review_queue` table as the API and the GUI.

Sources: [./lib/sfl/analysis/knowledge_base_source.rb](lib/sfl/analysis/knowledge_base_source.rb), [./lib/sfl/store/pg_review_queue_repository.rb](lib/sfl/store/pg_review_queue_repository.rb)

### Ingest Orchestrator

A parallel queue, `ingest_review_entries`, is maintained by `SFL::Ingest::Orchestrator`. It is not the content-review queue: it tracks files the orchestrator cannot confidently dispatch (low-confidence classification, an unrecognized format, or a failed loader draft). It uses the same shape convention — UUID primary key, `status` defaulting to `"pending"`, indexed on status — so a future UI/CLI review subcommand needs no new schema. The important invariant is that a failed merge in the knowledge-base compiler's compile loop (one malformed vault file) does not abort the rest of a batch, and one file's ingest issue never halts the pass.

Sources: [./db/migrations/009_create_ingest_review_entries.rb](db/migrations/009_create_ingest_review_entries.rb), [./lib/sfl/ingest/orchestrator.rb](lib/sfl/ingest/orchestrator.rb)

## Data-Model Boundaries by Cut

The queue slices are deliberately scoped to what this review exists for — content the model produces before it is stored:

| Slice | Table | Reviews | Consumer |
|---|---|---|---|
| Content-review queue (this page) | `review_queue` | Whether generated text is trustworthy before it is stored | API (`GET/POST /review-queue*`), GUI, KB compiler, CLI ingest loop |
| Annotation-audit trail | `annotation_reviews` (migration `006`) | Pass 2 annotation confidence on already-trusted text | `POST /clauses/:id/review` via `ClauseReviewService` |
| Ingest-review entries | `ingest_review_entries` (migration `009`) | Unclassifiable or low-confidence ingest files | `Ingest::Orchestrator` |

The clearest architectural statement in the repo is the migration comments themselves: `007` says the queue tracks whether the underlying text is correct *before it's ever permanently stored*; `006` says annotation reviews track confidence on text *everyone already trusts*.

Sources: [./db/migrations/007_create_review_queue.rb](db/migrations/007_create_review_queue.rb), [./db/migrations/006_create_annotation_reviews.rb](db/migrations/006_annotation_reviews.rb), [./db/migrations/009_create_ingest_review_entries.rb](db/migrations/009_create_ingest_review_entries.rb)

## How a Decision Reaches Storage

`edit` and `reject` both reach storage through `Core::Pipeline` (and therefore `Core::ClauseStore`), not through the repository. `replace_document` is the single write entry point: it deletes and reinserts atomically under one `document_id`, so a re-run of the same document never leaves stale clauses behind.

Sources: [./app/routes/review_queue.rb](app/routes/review_queue.rb), [./lib/sfl/store/pg_clause_store.rb](lib/sfl/store/pg_clause_store.rb), [./lib/sfl/core/ports/clause_store.rb](lib/sfl/core/ports/clause_store.rb)

## Testing Strategy

The queue and its consumers are tested at three levels:

1. **Repository level (`spec/store/pg_review_queue_repository_spec.rb`)** — exercises `enqueue`, `find`, `pending`, and `decide` against a real (test) Postgres. Covers the Sequel boundary bug: a bare `Symbol` value renders as an unquoted SQL identifier, so `content_type` and `source_type` are coerced to `String`; `pending` scopes by modality and excludes `approved`/`edited`/`rejected` rows; `decide` round-trips into the mapped status.
2. **Component level (`spec/gui/review_queue_view_model_spec.rb`)** — the viewmodel is unit-tested with injected doubles and no display. Covers modality scoping, selection preservation across refresh, negative/past-end index handling, the worker/thread-safe split of `compile_for_recompile!` vs `finish_recompile!`, and the `SELECTION_CHANGED_MESSAGE` guard.
3. **App level (`spec/gui/review_queue_app_spec.rb`)** — exercises startup (including the `SFL_REVIEWER_NAME` failure fast path), the auto-refresh ticker, and reviewer attribution.

Error policy is consistent across all three: the GUI rescues `StandardError` and logs, the repository rescues nothing at the repo level but documents its exceptions, and the API returns `ArgumentError` (HTTP 400) or `404` — never an escaping exception.

Sources: [spec/store/pg_review_queue_repository_spec.rb](spec/store/pg_review_queue_repository_spec.rb), [spec/gui/review_queue_view_model_spec.rb](spec/gui/review_queue_view_model_spec.rb), [spec/gui/review_queue_app_spec.rb](spec/gui/review_queue_app_spec.rb), [spec/api/clause_review_service_spec.rb](spec/api/clause_review_service_spec.rb), [spec/store/pg_clause_store_spec.rb](spec/store/pg_clause_store_spec.rb)

## Design Rules Worth Remembering

- **One decision value, three storage states.** `ReviewQueueDecision` is the API; `status` (`approved`/`edited`/`rejected`) is the persisted reality.
- **Repository never writes `edited_text`.** `Store::PgReviewQueueRepository#decide` is record-only; the caller always owns recompile and store.
- **Two separate audit tables for two separate questions.** `annotation_reviews` audits annotation confidence on trusted text; `review_queue` audits whether generated text is itself trustworthy. They share the "plain-string-key, no-FK, pending-by-default" convention but are not interchangeable.
- **Reject and edit both delegate to the pipeline.** The repository never mutates stored clauses; `Pipeline#compile` and `Pipeline#replace_document` are the only storage writers.
- **Reviewer attribution is a hard failure, not a default.** `SFL_REVIEWER_NAME` must be set before the GUI constructs, because a NULL reviewer would produce audit rows nobody can trace.
- **Stale selection is a first-class failure.** The 10-second auto-refresh, worker-thread compile, and main-thread UI binding all coexist without corrupting the audit trail.

Sources: [./lib/sfl/store/pg_review_queue_repository.rb](lib/sfl/store/pg_review_queue_repository.rb), [./lib/sfl/core/types/review_queue_decision.rb](lib/sfl/core/types/review_queue_decision.rb), [./lib/sfl/gui/review_queue_app.rb](lib/sfl/gui/review_queue_app.rb), [./lib/sfl/gui/review_queue_view_model.rb](lib/sfl/gui/review_queue_view_model.rb), [./app/routes/review_queue.rb](app/routes/review_queue.rb)

## Next Section

If you want to understand how content review connects to the annotation audit trail, read [Clause Reviews](clause-reviews). For the pipeline mechanics that `edit` and `reject` delegate to, read [Core Pipeline Orchestration](core-pipeline-orchestration).