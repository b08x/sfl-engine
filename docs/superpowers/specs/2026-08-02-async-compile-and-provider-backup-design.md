# Async compile jobs + LLM backup-provider fallback

Date: 2026-08-02
Status: approved for planning

## Context

The `sfl-api` service (`lib/sfl/api/server.rb`) is fully synchronous today:
`POST /pipeline/compile` runs Pass 1 + Pass 2 inline and blocks the HTTP
connection until the whole document/conversation is compiled. This was a
deliberate simplification — the previous async job-workflow surface
(`POST /workflows`, `GET /workflows/:id/status`, backed by Gush/Sidekiq) was
*deleted*, not fixed, when `sfl-jobs` was dropped, specifically because it
produced F2 (an async compile path writing a schema no consumer ever read).
See `lib/sfl/api/server.rb:9-19`.

A Python CrewAI project (`crews/sfl_geb_compiler_v1_crewai-project`) is
expected to call `sfl-api` as an external tool. Two gaps this raises:

1. **Timeout risk**: a large conversation's synchronous compile could exceed
   HTTP/proxy timeouts between CrewAI and `sfl-api`. No concrete failure yet
   — this is preemptive.
2. **LLM call reliability**: `Engine` (`lib/sfl/llm/engine.rb`) holds exactly
   one provider/model per task and degrades straight to a static untrusted
   default (`LLM::Degradation`, `annotation_source: "fallback"`) on any LLM
   failure. Legacy's DSPy-based `PassTwoEngine` had a full
   `ProviderFallback` chain; it wasn't removed for a documented reason of
   its own — it was collateral scope-reduction inside track decision 7
   (DSPy dropped project-wide in favor of `ruby_llm`). `engine.rb:11-19`
   notes "one provider per Engine instance" as that rewrite's simplified
   scope, not a rejection of fallback chains as a concept.

Both gaps are addressed here as two independent pieces — nothing requires
them to ship together, and each can be implemented/tested/reverted on its
own.

## Explicit non-goals

- **No DAG/workflow engine.** Gush solves fan-out/fan-in across dependent
  jobs; nothing here has that shape (confirmed with the user — the async
  compile is a single sequential pipeline run, not turns fanned out across
  workers). Reimplementing Gush would be bringing back a tool built for a
  problem this doesn't have.
- **No Redis/Sidekiq.** Redis exists in `docker-compose.yml` but is
  currently unconsumed by any Ruby code (no `redis` gem in the Gemfile).
  Introducing it as a queue backend is out of scope until the simpler
  Postgres-backed approach proves insufficient.
- **No automatic crash-resume for async jobs.** If the API process dies
  mid-job (restart, deploy, OOM), the job row is orphaned at `running`
  forever. The caller re-submits. No staleness detection, no reclaim loop.
  This is a deliberate scope cut, not an oversight — revisit only if it
  becomes a real operational problem.
- **No new annotation-source trust tier.** `TRUSTED_ANNOTATION_SOURCES`
  (`lib/sfl/core/types/trusted_annotation_sources.rb`) distinguishes "real
  model output" from "compiler-substituted default," not which model
  answered. Backup-provider output keeps `annotation_source: "llm"`; which
  provider actually responded is logged, not modeled as data.

## Piece 1 — Async compile jobs

### Architecture

- New `jobs` table (migration): `id uuid pk, kind text, status text
  (pending|running|done|failed), payload jsonb, result jsonb, error text,
  created_at, updated_at`.
- New `SFL::Store::PgJobRepository`, same shape/conventions as
  `PgReviewQueueRepository`.
- `POST /pipeline/compile`:
  1. Validate request params synchronously — unchanged, still a 400 before
     any row exists.
  2. Insert a `pending` row via `PgJobRepository`.
  3. Spawn a `Thread` running the job body (see below).
  4. Respond `202 {job_id:}` **immediately**, before the thread does any
     work. The row must be committed and visible to a `GET /jobs/:id` call
     that races the response.
- New `GET /jobs/:id` → `{status:, result?:, error?:}`, same response
  pattern as `GET /review-queue`.

### Job thread body

```
mark row "running"
begin
  result = <the exact synchronous pipeline call that runs today>
  mark row "done", result: result
rescue => e
  mark row "failed", error: e.message
end
```

The `begin/rescue` must be explicit inside the thread body — Ruby silently
swallows unhandled exceptions in a bare `Thread` (they don't surface without
`Thread#join` or `abort_on_exception`), and `abort_on_exception` would crash
the whole API process rather than just failing the one job.

`SpacySidecarParser`'s existing `@mutex` (`spacy_sidecar_parser.rb:33,41`)
already makes concurrent background jobs safe against the one shared
sidecar subprocess — no new synchronization needed there.

### Testing

- `PgJobRepository` CRUD spec.
- Server spec proving `POST /pipeline/compile` returns before the
  background work finishes — drive ordering with a `Queue`/
  `ConditionVariable` around a fake slow pipeline collaborator, not a real
  `sleep`.
- `GET /jobs/:id` spec covering all four statuses (`pending`, `running`,
  `done` with `result`, `failed` with `error`).

## Piece 2 — Backup provider/model fallback

### Architecture

- `TaskConfig` (`lib/sfl/llm/task_config.rb`) gains an optional `backup`
  attribute: another `TaskConfig`-shaped `{model, provider, params}`,
  `nil` by default.
- `Boot.task_config_from_env` (`lib/sfl/boot.rb:229`) reads a new
  `SFL_TASK_<NAME>_BACKUP_MODEL` / `SFL_TASK_<NAME>_BACKUP_PROVIDER` pair
  per task, same ENV convention as the existing primary triple. Unset →
  `backup: nil` → today's exact behavior (regression case).
- `Engine` (`lib/sfl/llm/engine.rb`) goes back to holding two providers:
  constructor gains `backup_chat:` (optional), building
  `backup_clause_annotator`/`backup_batch_clause_annotator` the same way it
  already builds the primary pair from `chat:`. The class comment at
  `engine.rb:11-19` ("no provider-fallback chain... one provider per Engine
  instance") gets corrected to describe the new shape — not left stale.
- `fetch_single`/`fetch_batch`: on the primary call's exception, if a
  backup annotator is present, log a warning and retry once against it.
  Only fall through to `Degradation` if the backup also fails, or wasn't
  configured — identical to today when `backup` is absent.
- Each provider attempt goes through `Breaker` under a distinct key
  (`"pass_two.annotate"` vs. `"pass_two.annotate.backup"`, and the batch
  equivalents) so a tripped primary circuit doesn't block backup attempts,
  and vice versa.

### Testing

- `TaskConfig`/`Boot.task_config_from_env` spec for the new
  `_BACKUP_MODEL`/`_BACKUP_PROVIDER` parsing, including the unset → `nil`
  default case.
- `Engine` spec additions:
  - primary fails, backup configured, backup succeeds →
    `annotation_source: "llm"` (no new trust tier).
  - primary fails, backup configured, backup also fails → existing
    `Degradation` default, as today.
  - primary fails, no backup configured → existing `Degradation` default,
    as today (regression test — proves the no-backup path is untouched).

## Open questions for the implementation plan

- Exact `jobs` table indexing (status, created_at) if polling volume ever
  matters — not addressed here, deferred to the plan/migration itself.
- Whether `POST /clauses/:id/review` should get the same async treatment —
  out of scope; nothing raised a concrete need for it, unlike
  `/pipeline/compile`.
