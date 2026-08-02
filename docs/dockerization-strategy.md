# Dockerization Strategy — API + WebUI as Services

**Status update (2026-08-02):** blockers 1-4 below are fixed (#17, #18, #33,
#34, #35), and the `api`/`migrate` services described in "Proposed service
topology" are built and live-verified — `docker compose --profile app build
api` builds cleanly, `docker compose --profile app up -d api` reaches Docker
`healthy` against `/health`. Two additional boot bugs were found and fixed
during that verification (neither had ever been exercised before — the HTTP
API had never actually been booted end-to-end prior to this): `lib/sfl/boot.rb`
referenced the bare `RubyLLM` constant without requiring it (only worked
before because `SFL::CLI`, which does `require "ruby_llm"`, happened to load
first on every previously-tested path); and `SFL::API.build_context` was a
module method defined as a side effect of Zeitwerk autoloading
`api/context.rb`, which nothing ever triggered since `config.ru` — its only
caller — references `SFL::API.build_context` as a bare module method call,
not a reference to the `Context` constant. Moved to `Context.build` instead,
which is Zeitwerk-safe by construction. `webui` remains unbuilt pending
#22/#23.

**What this document is for**: the plan for running `sfl-api` and the future
web frontend (see `docs/claude-design-ui-prompt.md` and issues #22-#32) as
proper containerized services alongside the Postgres/Redis containers that
already exist (`docker-compose.yml`). This is a strategy document, not an
implementation — it exists to surface real blockers in the current codebase
before writing Dockerfiles, and to get those blockers agreed/fixed first.

## Current state (verified against source, not assumed)

- `docker-compose.yml` already runs **postgres** (pgvector, host port 5433)
  and **redis** (redis-stack, host port 6380) as containers, both with
  healthchecks, both used only as *dependencies* — nothing in this repo
  runs inside a container today.
- `sidecar/Dockerfile` exists (a spaCy Pass-1 image) but is **orphaned** —
  nothing in `lib/sfl/boot.rb` or `SpacySidecarParser` ever invokes it.
  `Boot.resolve_pass1_command` only ever picks between a `bin/setup-python`-
  vendored interpreter (`.sfl-python/interpreter_path`) or a bare `python3`
  on PATH.
- `exe/sfl-api` runs via `bundle exec falcon serve -b http://localhost:PORT`.
- `config.ru` calls `SFL::DockerServices.ensure_running!` before booting —
  this shells out to `docker compose up` for the *app's own* Postgres/Redis
  dependencies.

## Four real blockers found while researching this (fix before/alongside building images)

### 1. `config.ru`'s `DockerServices.ensure_running!` call cannot run inside a container
It exists so a bare-metal `bundle exec sfl-api` auto-starts its own
Postgres/Redis. Inside a container, this is actively wrong: it would need
the host's Docker socket bind-mounted into the API container (a real
security exposure, and the wrong dependency direction — Compose itself
should own startup ordering via `depends_on` + `condition:
service_healthy`, not have a *service* shelling out to `docker compose up`
on itself). **This must be disabled for containerized runs.**

This is exactly what open issues **#17** ("Gate SFL Docker Compose
auto-start behind explicit opt-in") and **#18** ("Probe Docker daemon
availability and never raise from ensure_running!") already describe —
they were filed from a different angle (a bare-metal user without Docker
running) but the fix is the same fix this strategy needs: an explicit
opt-in (e.g. `SFL_DOCKER_AUTOSTART=1`, defaulting off) rather than
"unconditional whenever the Compose CLI is installed." **Treat #17 as a
prerequisite for this work**, not a parallel unrelated bug.

### 2. `exe/sfl-api` binds `localhost`, not `0.0.0.0` — tracked as #33
`falcon serve -b http://localhost:#{port}` binds the loopback interface
only. Inside a container, nothing outside that container's network
namespace — not even another container on the same Compose network — can
reach a `localhost`-bound server. This silently "works" in every local/bare-
metal run (where the developer *is* on `localhost`) and silently breaks the
moment it's containerized. Needs a `HOST` env var (default `0.0.0.0` in the
image, or conditionally `localhost` outside one) threaded into the bind
address.

### 3. Pass 1 (spaCy) needs to exist *inside* the API image, not as a sibling container — tracked as #34
`sfl-api`'s `POST /pipeline/compile` route drives the full two-pass
pipeline, including Pass 1. Spawning a *separate* `sfl-spacy-sidecar`
container per compile call (reusing the orphaned `sidecar/Dockerfile` as-is)
would require the API container to itself have Docker access (same
socket-mount problem as blocker #1) just to shell out `docker run`. The
straightforward fix: bake spaCy directly into the API image's system
Python — `sidecar/Dockerfile`'s own approach (`pip install spacy && spacy
download`) is already exactly right for this, it's just not currently
reused anywhere. Since `Boot.resolve_pass1_command` returns `nil` (and
`SpacySidecarParser` falls back to bare `python3` +
`sidecar/spacy_sidecar.py`) whenever `.sfl-python/interpreter_path` doesn't
exist, an image with `python3` + spaCy on the default system path needs
**zero** Ruby-side changes to work — `bin/setup-python`'s uv-vendoring
machinery is solving a different problem (diverse, non-containerized host
machines) that doesn't apply inside an image the team fully controls.

### 4. CORS origins are hardcoded, not env-configurable — tracked as #35
`lib/sfl/api/server.rb:50` hardcodes
`CORS_ORIGINS = %w[http://localhost:3000 http://127.0.0.1:3000]`. Whatever
origin the containerized `webui` actually serves from won't reliably be
one of those two literals once both services are behind Compose networking
and/or a reverse proxy. Needs to become env-configurable before `webui` can
call `api` from a browser. Detailed further in the `webui` section below.

## Proposed service topology

```
docker-compose.yml (extended)
├── postgres        existing — pgvector, 5433:5432
├── redis           existing — redis-stack, 6380:6379
├── api             NEW — Ruby/Falcon, lib/sfl/api, depends_on: postgres, redis (healthy)
├── migrate         NEW — one-shot, same image as api, `rake db:migrate`, run via `docker compose run --rm migrate`
└── webui           NEW — frontend from issues #22-32; dev-mode and prod-mode differ (see below)
```

### `api` service
- **Dockerfile**: multi-stage. Stage 1 installs Ruby deps
  (`bundle install`) and Python/spaCy (mirroring `sidecar/Dockerfile`'s
  simple `pip install spacy~=3.8 && spacy download en_core_web_sm`, not
  `bin/setup-python`'s uv-vendoring dance — that machinery targets
  arbitrary host machines, not a controlled image). Stage 2 (or the same
  stage, kept single for simplicity — no compiled asset step on the Ruby
  side) copies the app in and sets the entrypoint to `exe/sfl-api`.
- **Environment**: `DATABASE_URL` pointed at the Compose service DNS name
  (`postgresql://sfl:sfl@postgres:5432/sfl_engine_dev`, not
  `localhost:5433` — that host-port remap only exists for bare-metal-vs-
  local-Postgres conflict avoidance, irrelevant inside the Compose
  network), `REDIS_URL` similarly at `redis:6379`, `SFL_DOCKER_AUTOSTART`
  unset/`0` (blocker #1), `HOST=0.0.0.0` (blocker #2), plus the full
  provider/model/API-key surface already in `.env`
  (`SFL_TASK_*_PROVIDER`/`_MODEL`, `ANTHROPIC_API_KEY`/`MISTRAL_API_KEY`/
  etc., `LANGFUSE_*`) — supplied via an env file or Compose `secrets`, not
  baked into the image.
- **Healthcheck**: `GET /health` (already exists, `lib/sfl/api/server.rb`),
  same pattern as postgres/redis's `healthcheck:` blocks.
- **No volume needed** — stateless; Pass 1's Python deps are baked into
  the image at build time, not vendored into a runtime-mounted directory.

### `migrate` service
The codebase has an explicit, documented decision: **no auto-migration**
(`AGENTS.md`'s own "Gotchas" section, `SFL::Boot` never runs migrations).
Containerizing should *respect* that decision, not quietly override it for
convenience by running migrations in the `api` service's entrypoint. A
one-shot `migrate` service — same image as `api`, command overridden to
`bundle exec rake db:migrate`, run explicitly via `docker compose run --rm
migrate` (or as an init step in a deploy pipeline) — keeps migrations a
deliberate, visible action instead of a silent side effect of `api`
starting up.

### `webui` service — two modes, because the frontend doesn't exist yet
Issues #22-32 haven't landed, so this part of the strategy is necessarily
provisional on decisions those issues still need to make (framework
choice, issue #22).
- **Dev mode**: a Node-based dev server (Vite or equivalent, once #22
  picks a stack) with hot reload, proxying `/api/*` (or similar) to the
  `api` service by its Compose DNS name — mirrors how `api` reaches
  `postgres`/`redis` by service name today.
- **Prod mode**: a build stage producing static assets, served by a
  minimal static server (nginx/Caddy) or, if the eventual frontend is
  simple enough, by `sfl-api`'s own Falcon process serving a static
  directory — a real choice to make once #22/#23 land, not decided here.
- **CORS**: `lib/sfl/api/server.rb:50` hardcodes
  `CORS_ORIGINS = %w[http://localhost:3000 http://127.0.0.1:3000]` — not
  env-configurable today. This is a **fourth blocker**, same category as
  1-3 above: whatever the `webui` container's actual origin ends up being
  (a dev-server port, a prod static host, possibly not `localhost` at all
  once both services are containerized and reached through published
  ports or a reverse proxy), it needs to either already be in that literal
  array or the array needs to become env-configurable
  (`SFL_API_CORS_ORIGINS`-style) before `webui` can call `api` from a
  browser. File this as its own issue alongside #17/#18 rather than
  discovering it live once #22/#23 land.

## Networking
Default Compose bridge network is sufficient — service-name DNS resolution
(`postgres`, `redis`, `api`) replaces every `localhost:<remapped-port>`
reference used for bare-metal-vs-host-conflict avoidance today. Host port
publishing (`ports:`) stays relevant for `api` (developer/browser access)
and optionally `webui` in dev mode; `postgres`/`redis` could drop their
host `ports:` entirely in a "fully containerized" profile since only `api`
needs to reach them — but bare-metal `sfl-analyze` CLI usage (which isn't
being containerized here) still needs that host access, so don't remove
those `ports:` mappings without confirming the CLI workflow is out of
scope for this effort.

## Suggested phased rollout
1. **Prerequisite**: land issue #17 (gate Docker auto-start behind opt-in)
   — blocker #1 above is a strict dependency, not parallelizable.
2. Fix `exe/sfl-api`'s bind address (blocker #2) — small, independent,
   should land regardless of containerization timing since it's a real
   bug for *any* non-bare-metal deployment (a reverse proxy in front of it
   on the same host would hit the same issue).
3. Build and validate the `api` Dockerfile + Compose service in isolation
   (against the existing `postgres`/`redis` services) — no webui
   dependency, can start immediately once 1-2 land.
4. Add the `migrate` one-shot service.
5. Make CORS origins env-configurable (blocker #4) — small, independent of
   the webui stack choice, should land before #30/#32 (the two screens
   that actually call the API from a browser) start real integration.
6. WebUI containerization follows once issues #22/#23 (frontend scaffold +
   design system) have picked a concrete stack — this strategy's `webui`
   section will need a follow-up pass once that's real, not before.

## Open decisions needing your input
- Confirm `SFL_DOCKER_AUTOSTART`-style env var name/default (or whatever
  #17 lands on) so this doc's `api` service config matches the real
  fix, not a guessed name.
- Static-serving choice for `webui` prod mode (nginx/Caddy sidecar vs.
  Falcon-served static dir) — deferred above, but worth deciding early if
  it affects #22's framework choice.
- Whether `postgres`/`redis` should drop host port publishing in a
  "fully containerized" profile, or always keep it for bare-metal CLI
  compatibility (see Networking section).
