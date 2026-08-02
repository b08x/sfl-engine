# Async compile jobs + LLM backup-provider fallback

Date: 2026-08-02
Status: approved for planning
Revised: 2026-08-02 — reconciled against open GH issues #29 and #36-43 (see
"Related work" below); this revision supersedes the original Piece 1 shape.

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

## Related work (existing open issues)

Checked against `gh issue list` after the initial draft — two direct
overlaps changed this spec's shape:

- **#29** ("Backend: batch upload/ingestion HTTP API — `POST /uploads`,
  `GET /uploads/:job_id`") needs the same background-job infrastructure
  Piece 1 needs, but with richer requirements: per-file status, not one
  job = one result; an export-expansion step producing nested child rows
  (one raw ChatGPT/Claude export `.json` → N conversation rows, each
  independently trackable); reuse of the CLI's existing F11
  partial-failure isolation. It also independently raises the exact
  Redis/Sidekiq question this spec already answered ("check whether redis
  ... is meant to back this ... before building bespoke job
  infrastructure"). **Piece 1 below is redesigned to be the shared
  infrastructure #29 needs**, not a narrower `/pipeline/compile`-only
  version built in isolation — see "Piece 1" for the resulting shape.
- **#36-43** (Query Router, `services/router/`,
  `.specs/plans/sfl-query-router.design.md`) is a separate planned
  service whose `Dispatcher` (#40) calls the same `LLM::ChatFactory`/
  `LLM::Config` Piece 2 touches, and whose design doc states a deliberate
  non-goal: *"no retry logic on LLM dispatch... a second, invisible retry
  layer underneath would make failures harder to reason about, not
  easier. Report plainly, let the caller decide."* That reasoning is
  aimed at `/route`'s caller (an external agent/RAG pipeline that can
  retry itself) — see "Piece 2 vs. the router's no-retry stance" below
  for why Piece 2 still applies to `Engine`/Pass 2 despite this.

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

## Piece 1 — Async jobs (shared with #29)

This is no longer scoped to `/pipeline/compile` alone. It's the generic
background-job infrastructure both `/pipeline/compile` (one job, one
result) and #29's `/uploads` (one job, many per-file/per-conversation
child results, some of which expand into further children) need — designed
against #29's requirements, with `/pipeline/compile` as the simplest
possible consumer of the same schema.

### Architecture

- New `jobs` table (migration): `id uuid pk, kind text, status text
  (processing|done), payload jsonb, created_at, updated_at`. `status`
  tracks only whether the job has finished *attempting* all its items —
  per-item outcomes (including failures) live on `job_items`, per F11
  partial-failure isolation: one item's failure never blocks reporting on
  the rest, and never flips the parent job to a blanket "failed."
- New `job_items` table: `id uuid pk, job_id fk, parent_item_id fk
  (nullable, self-referential — set when a raw export `.json` expands into
  per-conversation children), label text, kind text, status text
  (queued|processing|embedded|failed), clause_count integer (nullable),
  result jsonb (nullable), error text (nullable), created_at, updated_at`.
- New `SFL::Store::PgJobRepository`, same shape/conventions as
  `PgReviewQueueRepository`, covering both tables.
- `POST /pipeline/compile`:
  1. Validate request params synchronously — unchanged, still a 400 before
     any row exists.
  2. Insert a `processing` `jobs` row (`kind: "pipeline_compile"`) with
     exactly one `job_items` row (`queued`).
  3. Spawn a `Thread` running the item body (see below) for that one item.
  4. Respond `202 {job_id:}` **immediately**, before the thread does any
     work. The rows must be committed and visible to a `GET /jobs/:id`
     call that races the response.
- `POST /uploads` (#29's endpoint, built on the same infrastructure):
  1. Insert a `processing` `jobs` row (`kind: "upload"`) with one
     `job_items` row per input file.
  2. Raw ChatGPT/Claude export `.json` files get an explicit expansion
     step first: reuse `Analysis::ChatExportExpander` to enumerate
     conversations, then insert one child `job_items` row per conversation
     (`parent_item_id` set), reporting "Expanding export… found N
     conversations" on the parent item before its children exist.
  3. Spawn one thread per top-level item (files that aren't raw exports)
     or per expanded child (conversations from an expanded export),
     reusing the CLI's existing per-file rescue behavior
     (`SFL::CLI.run_conversation`) rather than inventing new
     failure-isolation logic.
  4. Respond `202 {job_id:}` immediately, same as compile.
- `GET /jobs/:id` → `{status:, items: [{id:, label:, kind:, status:,
  clause_count:, error:, children:}]}`. For `/pipeline/compile`'s
  single-item job, the one item's `result`/`error` *is* the whole answer;
  callers that only care about compile don't need to think about the
  `items` array's general shape, just `items[0]`.

### Item thread body

```
mark item "processing"
begin
  result = <the exact synchronous per-item work that runs today —
            the whole compile pipeline for /pipeline/compile,
            run_conversation's per-file body for /uploads>
  mark item "embedded", result: result
rescue => e
  mark item "failed", error: e.message
  # parent job's own status is untouched — F11: this item's failure
  # doesn't block the rest
end
```

The `begin/rescue` must be explicit inside each thread body — Ruby
silently swallows unhandled exceptions in a bare `Thread` (they don't
surface without `Thread#join` or `abort_on_exception`), and
`abort_on_exception` would crash the whole API process rather than just
failing the one item.

`SpacySidecarParser`'s existing `@mutex` (`spacy_sidecar_parser.rb:33,41`)
already makes concurrent item threads safe against the one shared sidecar
subprocess — no new synchronization needed there.

### Testing

- `PgJobRepository` CRUD spec, covering parent/child `job_items` and the
  expansion case.
- Server spec proving `POST /pipeline/compile` and `POST /uploads` both
  return before background work finishes — drive ordering with a
  `Queue`/`ConditionVariable` around a fake slow item collaborator, not a
  real `sleep`.
- `GET /jobs/:id` spec covering: single-item compile job in each status;
  multi-item upload job with a mix of `embedded`/`failed` items (proving
  one failure doesn't flip the parent or block the others); an
  export-expansion job showing parent + children.

### Sequencing note

This piece should be planned/implemented as (or alongside) #29, not as a
standalone `/pipeline/compile`-only effort — the schema above is sized for
#29's requirements specifically so it doesn't need reshaping once #29 is
picked up.

## Piece 2 — Backup provider/model fallback

### Piece 2 vs. the router's no-retry stance

`services/router/`'s `Dispatcher` (#40) and this piece's `Engine` both sit
on top of `LLM::ChatFactory`/`LLM::Config`, and the router's design doc
explicitly rejects invisible retry: *"a caller building its own agent/RAG
pipeline almost certainly already has a retry/fallback policy... report
plainly, let the caller decide."* Piece 2 keeps backup fallback anyway,
because the two call sites don't share the property that argument depends
on:

- `POST /route` is a **live, single-shot, agent-visible** call. CrewAI
  makes the call, sees the result (or the `502 {error: "dispatch_failed",
  ...}`) directly, and is in a position to decide whether to retry, with
  what policy, against what fallback — exactly the caller this codebase's
  design doc has in mind.
- `Engine#annotate`/`#annotate_batch` runs **deep inside an unattended
  internal loop** (Pass 2, one call per clause, potentially hundreds per
  document) that `sfl-analyze`/`sfl-api` drives on its own. CrewAI never
  sees, and couldn't meaningfully retry, one clause's annotation call —
  there is no external caller to "let decide." The only two options at
  that point are: substitute a static untrusted default immediately
  (today's behavior), or try one more real model first. Backup fallback
  here doesn't hide a failure from a caller who could have retried it —
  there is no such caller at that granularity.

If a future change makes individual clause annotations independently
visible/retryable to an external caller, this reasoning should be
revisited.

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
