# Ecosystem Architecture — sfl-engine + syncopated-context-compiler

**Status:** Target-state frame. Accepted as the shared reference for work in *either* repo.
Phase 0 open questions (§9.1, §9.2) resolved 2026-09-13.
**Created:** 2026-09-13
**Scope:** Cross-repo. This document sits in `sfl-engine` because the engine is the
component the rest of the suite composes around, and because it extends
`docs/dockerization-strategy.md` (which already covers the Compose-era service topology).
Agents working in `syncopated-context-compiler` should read this before touching
`src/lib/graph/` or `server.ts`.

**Durable record:** trackboi track `track-ecosystem-architecture-engine-visual-driver-*`
(created in both repos, cross-referencing rather than duplicating the existing tracks).

---

## 1. Why this document exists

Two sibling projects have been maturing independently:

- **sfl-engine** — Ruby. Ingest, SFL annotation, hybrid retrieval, synthesis, topic modeling.
  Real CLI, real TUI, real HTTP API, Postgres/pgvector storage.
- **syncopated-context-compiler (SCC)** — TypeScript/React 19 + Vite + Express. Compiles
  JSON conversation exports from provider web UIs into a browser-native knowledge graph,
  then distills trajectories into `SKILL.md` artifacts.

They have been treated as separate programs with an integration seam between them. The
reframing is that they are **one ecosystem with one engine and one visual driver**:

> sfl-engine is refactored from a local prototype into a standardized contextual hybrid
> search and retrieval ecosystem. syncopated-context-compiler is adapted and expanded into
> the visual driver of that engine. SCC's current conversation-compiler becomes a subfeature
> rather than the whole product. sfl-engine remains usable standalone as a CLI with an
> optional TUI. The entire suite deploys as a Podman pod with shared volumes.

Nothing below asks either codebase to throw work away. The conversation-compiler is
preserved intact; what changes is its *position* in the system.

---

## 2. Current state — verified, not assumed

Every claim in this section was checked against source this session. Several correct
assumptions that were previously in circulation.

### 2.1 sfl-engine

| Fact | Evidence |
|---|---|
| Mid-migration to Roda. `app/sfl.rb` is the live Roda app; routes are hash branches in `app/routes/` — `clauses`, `graph`, `health`, `pipeline`, `retrieve`, `review_queue`, `synthesize` | `app/sfl.rb`, `app/routes/*.rb` |
| `lib/sfl/api/server.rb` is the **legacy** Rack shell, retained only until Roda request-spec parity, then deleted | `docs/dockerization-strategy.md` status update 2026-09-12 |
| **`GET /graph/nodes` and `GET /graph/edges` already exist.** Edges combine `parent_child_edges` (structural) with `semantic_neighbors` (semantic) | `app/routes/graph.rb` |
| CORS is already implemented as an origin allowlist (`apply_cors`, `Providers::Engine.cors_origins`) — a browser driver is an *anticipated* client, not a new idea | `app/sfl.rb` |
| `Providers::Engine` wraps `SFL::API::Context.build`, so Roda routes and the CLI share **one composition root** | `app/config/providers/engine.rb`, `boot.rb` |
| Four usage modes exist today: `exe/sfl-analyze` (CLI), `exe/sfl-tui` (TUI, `lib/sfl/tui/`), `exe/sfl-review` (Glimmer desktop GUI), `exe/sfl-api` (Falcon → `config.ru` → Roda) | `exe/` |
| Compose already runs `postgres` (pgvector, 5433), `redis` (6380), plus `api` and `migrate` behind the `app` profile, healthchecked, with `SFL_AUTO_START_DOCKER=0` inside the container | `docker-compose.yml`, `docker/api.Dockerfile` |
| `sidecar/Dockerfile` (spaCy) exists but is **orphaned** — `Boot.resolve_pass1_command` only selects `.sfl-python/interpreter_path` or bare `python3` | `docs/dockerization-strategy.md`, `sidecar/` |
| `sidecar/spacy_sidecar.py` establishes the NDJSON-over-stdio pattern the BERTopic sidecar reuses | `sidecar/spacy_sidecar.py` |

### 2.2 syncopated-context-compiler

| Fact | Evidence |
|---|---|
| `src/lib/graph/` holds `builder.ts` (export parsers), `embeddings.ts` (browser TF-IDF `Vectorizer`), `query.ts` (215-line graph query executor with its own schema DSL), `topic_extraction.ts` (LLM-prompted clustering) | `src/lib/graph/` |
| `src/lib/providers/` holds six LLM adapters — `proxy`, `ollama`, `google`, `groq`, `mistral`, `openrouter` — behind a `ModelProvider` interface | `src/lib/providers/`, `src/types/provider.ts` |
| `server.ts` (Express) exposes only `/api/health` and `/api/llm/*` (status, test, models, generate, stream, speak). It is an LLM proxy, not a data backend | `server.ts` |
| `GraphContext` is in-memory `useReducer` state. **Zero persistence** | `src/contexts/GraphContext.tsx`, `AGENTS.md` gotcha 8 |
| SCC's own `ROADMAP.md` Phase 2 (marked *active*) already names sfl-engine as the backend, with a diagram of UI → SFL Engine API → Postgres/Redis + spaCy/BERTopic sidecars | `ROADMAP.md` |

### 2.3 Corrections to previously circulating assumptions

1. **Routes moved.** The live HTTP surface is `app/routes/*.rb`, not `lib/sfl/api/server.rb`.
2. **Graph routes already exist.** `GET /graph/nodes` and `GET /graph/edges` were absent from
   earlier route inventories. They are the most consequential routes for this reframing —
   they are the server-side replacement for SCC's in-memory `ConvoGraph` plus `query.ts`.
3. **The engine has four modes, not two.** Alongside CLI and TUI there is a Glimmer desktop
   review GUI (`exe/sfl-review`) whose job substantially overlaps SCC's review surface.
4. **An ecosystem-shaped doc already existed.** `docs/dockerization-strategy.md` (223 lines)
   covers the Compose-era service topology. This document supersedes its *deployment target*
   (Compose → Podman pod) while preserving its blocker analysis, which remains accurate.

---

## 3. Target state

### 3.1 Shape

```
                       ┌──────────────────────────────────────────┐
                       │   syncopated-context-compiler (driver)   │
                       │  React 19 + Vite, Express LLM proxy      │
                       │                                          │
                       │  ┌────────────┐ ┌───────────┐ ┌────────┐ │
                       │  │ conversa-  │ │ retrieval │ │ review │ │
                       │  │ tion       │ │ / graph   │ │ queue  │ │
                       │  │ compiler   │ │ explorer  │ │        │ │
                       │  │ (SUBFEAT.) │ │  (NEW)    │ │        │ │
                       │  └────────────┘ └───────────┘ └────────┘ │
                       │        │  LLM adapters stay client-side  │
                       └────────┼─────────────────────────────────┘
                                │ HTTP (CORS allowlist)
        ┌───────────────────────┼───────────────────────┐
        │                       ▼                       │
  ┌─────────────────────────────────┐                │
  │           sfl-engine              │                │
  │  (unified executable w/ subcmds) │                │
  │                                 │                │
  │  ┌──────────┐ ┌──────────┐ ┌────────┐    │                │
  │  │ analyze │ │   tui   │ │  api   │    │                │
  │  │ (CLI)   │ │          │ │(daemon)│    │                │
  │  └──────────┘ └──────────┘ └────────┘    │  driving adapters │
  └─────────────────────────────────┘                │
                    │                                   │
       ┌────────────▼─────────────────────────┐         │
       │   Providers::Engine (composition)    │         │
       │   ── SFL::Core domain + use cases ── │  sfl-engine
       └────────────┬─────────────────────────┘         │
                    │                                   │
   ┌────────────────┼───────────────┬──────────────┐    │
   ▼                ▼               ▼              ▼    │
┌────────┐   ┌────────────┐  ┌───────────┐  ┌──────────┐│
│Postgres│   │   Redis    │  │  spaCy    │  │ BERTopic ││
│pgvector│   │            │  │  sidecar  │  │ sidecar  ││
└────────┘   └────────────┘  └───────────┘  └──────────┘│
                              NDJSON over stdio          │
                              + shared volumes           │
        ─────────────────────────────────────────────────┘
```

### 3.2 Architecture pattern

**Hexagonal (ports and adapters) at the engine, with the Podman pod as the composition
boundary.**

Justification grounded in current code, not preference: `Providers::Engine` is already a
single composition root shared by the CLI and the HTTP routes; the three in-flight refactor
specs (`SFL-EMB-*`, `SFL-ING-*`, `SFL-TOP-*`) are all written as ports-and-adapters designs;
and the accepted stdio-sidecar decision already treats Python components as driven adapters
behind a port rather than as peer services.

The consequence that matters: **SCC is one driving adapter among several, not a peer system.**
It sits in the same architectural position as the CLI and the TUI. It has no privileged access,
no shared code with the engine, and no path to the database that does not go through the HTTP
port.

**Sharpened, 2026-09-13: SCC is *a* pluggable frontend, not *the* frontend.** sfl-engine must
work completely independently of SCC and be callable by other apps. This is a stronger claim
than parity with the CLI/TUI — it means the HTTP API surface is designed, documented, and
evolved as a general-purpose contract usable by any client, not shaped around SCC's specific
needs. No route, payload shape, or behavior may assume SCC-specific concerns (its React state
model, its `ModelProvider` abstraction, its particular UI flows); if a route only makes sense
for SCC's UI, it belongs behind an SCC-side adaptation layer, not baked into the engine's API.

### 3.3 Responsibilities and boundaries

| Component | Owns | Must not own |
|---|---|---|
| sfl-engine domain (`lib/sfl/core`) | SFL types, clause/graph entities, retrieval filters | Any HTTP, React, or Podman awareness |
| sfl-engine use cases | Ingest orchestration, hybrid retrieval, synthesis, topic modeling, annotation | Presentation concerns |
| `app/routes/*` | HTTP driving adapter, CORS, wire serialization | Business logic |
| `exe/sfl-analyze`, `exe/sfl-tui` | CLI/TUI driving adapters | Anything the HTTP adapter cannot also reach |
| spaCy / BERTopic sidecars | Python NLP compute | Their own HTTP surface *(per accepted decision)* |
| Postgres + pgvector | All durable state for the ecosystem | — |
| SCC React app | Visualization, interaction, review workflow, distillation | Retrieval, embedding, persistence, topic modeling |
| SCC `server.ts` | LLM proxy for per-user keys (`/api/llm/*`) | Any second data or retrieval surface |

---

## 4. sfl-engine stays standalone — the tri-mode guarantee

This reframing does **not** make the engine depend on the frontend. Standalone usability is a
hard constraint, and it is already structurally protected:

1. **One composition root, many adapters.** `Providers::Engine` builds the object graph;
   `exe/sfl-analyze`, `exe/sfl-tui` and the Roda app all consume it. No capability may be
   implemented inside `app/routes/` — routes translate HTTP to use-case calls and nothing more.
   This is the invariant that keeps the CLI at feature parity for free.
2. **`SFL::Ingest::TargetResolver` is the single resolution path** for both the CLI argument
   and the HTTP request body (SFL-ING-19). Neither driving adapter constructs a `CorpusSource`
   directly. Same guarantee, applied to ingest.
3. **The TUI is a first-class mode, not a demo.** `lib/sfl/tui/` (`program.rb`, `layout.rb`,
   `workspaces/`, `app_context.rb`) is real and stays. In the pod, the TUI is reached by
   `podman exec` into the engine container, or run bare-metal against the pod's Postgres.
4. **The pod is optional.** Bare-metal `exe/sfl-analyze` against a local Postgres remains a
   supported path. The pod is a deployment convenience, not a runtime requirement.

**Acceptance test for the whole reframing:** if a change makes a capability reachable only
through SCC, the change is wrong — read as "reachable only through CLI/TUI/HTTP in general,"
not coupled to any single frontend, including SCC.

### 4.1 The fourth mode — accepted decision

**DECISION:** Retire `exe/sfl-review` and unify all modes under `sfl-engine` subcommands.

`exe/sfl-review` is a Glimmer DSL desktop GUI for the ingestion review queue
(track `track-review-queue-gui-1ia6caw`). Its job is the same job SCC's `/review` surface will
do, better and in the browser. Maintaining both is duplicated effort on the least-differentiated
surface in the suite.

**Accepted resolution, 2026-09-13:**
- `exe/sfl-review` is **deprecated immediately** and will be **retired** once SCC's review surface reaches parity against `POST /clauses/:id/review` and `POST /review-queue/:id/decide`.
- All four existing binstubs (`sfl-analyze`, `sfl-tui`, `sfl-api`, `sfl-review`) are **consolidated into a unified `sfl-engine` executable** with subcommands (`analyze`, `tui`, `api`, `gui`).
- The `gui` subcommand is **temporary** and will be removed alongside `exe/sfl-review` when SCC parity is achieved.
- The unified CLI design is specified in [`docs/refactor/CLI-HEXAGON-USER-STORIES.md`](refactor/CLI-HEXAGON-USER-STORIES.md).

---

## 5. SCC's prototype as a subfeature — concretely

SCC's own ADR philosophy is preserved: *conversations are first-class knowledge artifacts —
collect → review → extract lessons → codify into actionable artifacts.* The reframing does not
weaken that; it removes the browser's obligation to also be a database and a search engine, so
the compiler can be the thing it is good at.

The conversation compiler becomes **one ingest source among many**, sitting alongside the
filesystem-native session discovery already scoped in
`track-local-session-intelligence-provider-ingestion-0zw2t87`.

### 5.1 Module disposition

| SCC module | Verdict | Rationale |
|---|---|---|
| `src/lib/graph/builder.ts` (Claude/ChatGPT/Mistral parsers) | **Survives as-is** | This *is* the conversation-compiler subfeature. Zero-config, client-side, no provider needed. Later mirrored server-side as an ingest adapter for large exports. |
| `src/lib/graph/embeddings.ts` (TF-IDF `Vectorizer`) | **Subsumed** | Replaced by `POST /retrieve` against pgvector. Browser TF-IDF cannot match hybrid dense+sparse retrieval and cannot persist. Retain at most as an offline-only degraded path. |
| `src/lib/graph/topic_extraction.ts` | **Subsumed** | Replaced by the BERTopic sidecar behind the engine. LLM-prompted clustering in the browser is non-deterministic and unevaluable. |
| `src/lib/graph/query.ts` (215-line executor + schema DSL) | **Subsumed** | Replaced by `GET /graph/nodes` and `GET /graph/edges`, which already return structural parent/child edges and semantic neighbors. This is the largest single deletion and the clearest win. |
| `src/lib/providers/*` (6 LLM adapters) | **Survives, client-side** | Per-user API keys, local Ollama, user-visible model choice. The engine has its own dspy.rb LLM layer for server-side annotation; these are different concerns and should not be merged. |
| `src/lib/trajectory/compiler.ts` | **Survives** | Trajectory extraction is SCC's own domain, not retrieval. |
| `src/lib/distillation/orchestrator.ts` | **Survives** | Weak/strong/contrastive `SKILL.md` distillation stays a frontend-orchestrated workflow. |
| `src/lib/rating/store.ts` + `components/review/` | **Survives, rewired** | Point at `POST /clauses/:id/review`, `GET /review-queue`, `POST /review-queue/:id/decide` instead of local state. Absorbs `exe/sfl-review`'s role. |
| `src/contexts/GraphContext.tsx` | **Rewritten** | From in-memory source of truth to a cache over engine reads. The largest behavioral change in SCC. |
| `server.ts` (Express) | **Survives, narrowed** | Stays the `/api/llm/*` proxy. Must not grow a second retrieval or persistence surface. |
| `components/graph/`, `dashboard/`, `export/`, `settings/` | **Survive** | Presentation. Data sources change beneath them. |

### 5.2 Genuinely new frontend surface

1. **Ingest control** — drive `POST /ingest` per the SFL-ING-13 contract (202 + run record,
   `GET /ingest/runs/:id` polling, 409 on concurrent run). No equivalent exists in SCC today.
2. **Corpus browser** — the engine's corpus is far larger than one JSON export; SCC currently
   assumes the whole graph fits in memory.
3. **Retrieval / hybrid search UI** — filter controls over `RetrievalFilters`
   (mood, process_type, source_type, modality and tenor ranges). This is the "contextual hybrid
   search" surface the whole reframing is named for, and it does not exist on either side yet.
4. **Topic explorer** — BERTopic output, replacing the ad-hoc LLM topic list.
5. **Synthesis view** — `POST /synthesize` and `POST /pipeline/compile` results.

---

## 6. Integration contract

Reuse these; do not re-derive their shapes. Items marked *live* are implemented today.

| Route | Status | Purpose |
|---|---|---|
| `GET /health` | live | Pod healthcheck |
| `POST /retrieve` | live | Hybrid retrieval with `RetrievalFilters` |
| `POST /synthesize` | live | Context synthesis |
| `POST /pipeline/compile` | live | `AnnotatedClause[]` compilation |
| `GET /graph/nodes` | live | Graph nodes, optional `document_id` |
| `GET /graph/edges` | live | Structural parent/child + semantic neighbor edges |
| `GET /clauses`, `GET /clauses/review-queue`, `POST /clauses/:id/review` | live | Clause review |
| `GET /review-queue`, `POST /review-queue/:id/decide` | live | Ingest review queue |
| `POST /ingest`, `GET /ingest/runs/:id` | **specified, not built** | SFL-ING-13. Body is a source descriptor (`{type: filesystem, root:}` or `{type: git, repo:, ref:}`), returns 202 + run record, 409 while a run is active |

`POST /ingest` is fully specified and is **not** an open design question — SCC should integrate
against exactly that contract when it ships.

---

## 7. Podman pod topology — first-draft sketch

> **This is a sketch to anchor discussion, not production configuration.** Names, paths, and
> unit ordering are illustrative. It has not been run. It is here to make the shared-volume
> and stdio boundaries concrete enough to argue about.

Consistent with the accepted decision on
`track-dockerization-and-microservices-architecture-0f84yz9`: Podman Quadlets, shared volumes,
NDJSON over stdio for sidecars — **not** HTTP microservices.

```
[reverse proxy — outside the pod, terminates the public origin]
        │  published origin becomes the sfl-engine CORS allowlist value
        ▼
pod: sfl-suite
│  published: 8080 (SCC) , 3001 (engine API, loopback only)
│
├── sfl-postgres.container      pgvector/pgvector:pg16
│     volume: sfl-pgdata:/var/lib/postgresql/data
│
├── sfl-redis.container         redis/redis-stack
│     volume: sfl-redisdata:/data
│
├── sfl-engine.container        docker/api.Dockerfile → falcon → config.ru → Sfl (Roda)
│     volumes: sfl-corpus:/corpus          (ingest source, shared)
│              sfl-sidecar-io:/var/run/sfl (stdio handoff + spill files)
│     env: DATABASE_URL=postgresql://sfl:sfl@localhost:5432/sfl_engine_dev
│          SFL_AUTO_START_DOCKER=0
│          HOST=0.0.0.0
│     after: sfl-postgres, sfl-redis
│
├── sfl-spacy-sidecar.container   sidecar/Dockerfile  (currently ORPHANED — see §7.1)
│     volume: sfl-sidecar-io:/var/run/sfl
│
├── sfl-bertopic-sidecar.container  (not yet built — SFL-TOP-*)
│     volume: sfl-sidecar-io:/var/run/sfl
│
└── sfl-compiler.container       SCC: nginx or node serving Vite build + Express /api/llm/*
      env: VITE_SFL_API=http://localhost:3001
           OLLAMA_BASE_URL=<configured externally-reachable Ollama endpoint>
```

Because pod members share a network namespace, the engine reaches Postgres at `localhost:5432`
and SCC reaches the engine at `localhost:3001` — no service DNS and no published database port.
Only `8080` needs to leave the pod, and only via the reverse proxy in front of it — nothing binds
`8080` to the public interface directly.

**Ollama is not a pod member.** Resolved 2026-09-13: Ollama is treated as a provider API, exactly
like SCC's other remote LLM providers (Google/Groq/Mistral/OpenRouter) — reached over an
explicitly configured base URL, never assumed at `localhost`. This applies on both sides: SCC's
`OllamaAdapter` and the engine's own `SFL_TASK_EMBEDDING_` Ollama usage each take an explicit,
externally-reachable URL. Ollama therefore never appears as a unit in this pod.

`sfl-corpus` is the shared volume that makes CLI and API ingest equivalent: the same mounted
corpus is what `exe/sfl-analyze` walks bare-metal and what a `POST /ingest` filesystem source
descriptor resolves against.

### 7.1 Known blocker carried forward

`sidecar/Dockerfile` exists but nothing invokes it — `Boot.resolve_pass1_command` only selects
a `bin/setup-python`-vendored interpreter or a bare `python3` on PATH. **A pod cannot work until
the sidecar is reachable as a separate container process rather than a subprocess of the engine.**
This is the single largest unresolved engineering item between today and a working pod, and it
applies to the BERTopic sidecar identically. The blocker analysis in
`docs/dockerization-strategy.md` remains accurate and should be read alongside this section.

---

## 8. Phased path

A roadmap, not a task breakdown. Each phase is gated on the previous one.

**Phase 0 — Freeze the frame.** This document plus its trackboi tracks. **Done, 2026-09-13:**
the SCC-side retrieval contradiction (§9.1) is resolved, Ollama egress and browser-origin CORS
(§9.2) are resolved. No code.

**Phase 1 — Engine becomes pod-ready.**
Ship `POST /ingest` per SFL-ING-13. Un-orphan the spaCy sidecar so Pass 1 runs as a separate
container process over stdio + shared volume. Delete `lib/sfl/api/server.rb` once Roda request
specs reach parity. Land the in-flight `SFL-EMB-*` hexagon work.
*Gate: the engine runs headless in a container with no host Python and no Docker socket.*

**Phase 2 — SCC becomes a thin client.**
Rewrite `GraphContext` as a cache over `GET /graph/nodes` / `GET /graph/edges`. Retire
`query.ts`, `embeddings.ts`, `topic_extraction.ts`. Rewire the review surface to the clause and
review-queue routes. Keep `builder.ts` and the LLM adapters untouched.
*Gate: SCC renders a corpus it never parsed, from engine reads alone.*

**Phase 3 — New frontend surface.**
Ingest control, corpus browser, hybrid search UI with `RetrievalFilters`, topic explorer,
synthesis view. Conversation compiler is demoted in the navigation to one ingest source among
several. Decide `exe/sfl-review`'s retirement (§4.1).
*Gate: the visual driver drives capabilities the CLI has but the prototype never had.*

**Phase 4 — Pod assembly.**
Write the Quadlet `.container` units. Replace the Compose-era topology for deployment while
keeping Compose for local development if useful. Verify the tri-mode guarantee holds inside the
pod: CLI via `podman exec`, TUI via `podman exec`, API via the published port.
*Gate: `systemctl --user start sfl-suite` brings up the whole ecosystem.*

**Phase 5 — BERTopic migration.**
Replace tomoto/LDA with the BERTopic sidecar per `SFL-TOP-*`, as a second stdio sidecar in the
established pattern. Deliberately last: it is the only phase that needs the sidecar pattern to
already be proven in production by spaCy.

---

## 9. Resolved decisions and remaining open questions

### 9.1 RESOLVED — SCC's Local Session Intelligence tracks specify a second retrieval engine

Three SCC tracks created 2026-08-20 specified SCC building its **own** persistence and retrieval
stack:

- `track-local-session-intelligence-search-retrieval-back-0qlgvlv` — SQLite (WAL) + FTS5 BM25 +
  sqlite-vec KNN + Reciprocal Rank Fusion + parent/child chunking.
- `track-local-session-intelligence-analysis-insights-eng-1bg9glv` — GEPA prompt optimization via
  `@ax-llm/ax` + vector clustering with MMR dedup, feeding "the SQLite/vector backend from the
  retrieval track".
- `track-local-session-intelligence-provider-ingestion-0zw2t87` — filesystem-native session
  discovery across Claude Code JSONL, Gemini CLI, OpenCode, Crush, Mistral Vibe, Antigravity,
  Hermes Agent SQLite.

The first two duplicated, in TypeScript over SQLite, exactly what sfl-engine provides in Ruby over
Postgres/pgvector — hybrid retrieval, parent/child chunking, RRF, topic clustering. They were also
contradicted by SCC's own newer `ROADMAP.md` Phase 2 and by
`track-integrating-sfl-engine-as-backend-for-syncopated-1da4gpp`.

**Owner-accepted resolution, 2026-09-13:**

- *Search & Retrieval Backend* track — **retired.** sfl-engine is the ecosystem's single
  retrieval layer; SCC does not get a second one.
- *Analysis & Insights Engine* track — **relocated to the engine side.** Deterministic,
  evaluable, SFL-constrained analysis is exactly what the engine's dspy.rb layer is for. SCC
  keeps presentation of results only.
- *Provider Ingestion* track — **survives and relocates.** Filesystem-native session discovery is
  an ingest `CorpusSource` concern and belongs behind `TargetResolver` (SFL-ING-19). Its UI half
  stays in SCC as part of the ingest control surface. Its own accepted decision — that manual
  JSON-export upload stays a permanent path — is preserved exactly, and is in fact what §5.1
  keeps `builder.ts` for.

### 9.2 RESOLVED — pod networking: LLM egress and browser-origin CORS

- **Ollama, resolved.** Ollama is not a pod member and gets no special-cased pod-internal
  networking. It is treated exactly like SCC's other remote LLM providers — reached over an
  explicitly configured base URL, never assumed at `localhost`. Applies identically to SCC's
  `OllamaAdapter` and the engine's own `SFL_TASK_EMBEDDING_` Ollama usage. See §7.
- **Browser-origin CORS, resolved.** SCC is published behind a reverse proxy (not a raw pod port,
  not a bare hostname). The engine's CORS allowlist (`Providers::Engine.cors_origins`) takes that
  proxy's externally-published origin as its entry — one value in a config-driven,
  multi-origin-capable allowlist (per §3.2's "pluggable frontend" decision), set at deploy time,
  not hardcoded. The exact hostname/domain remains a deploy-time detail, not a design gap.

### 9.3 Unresolved — where server-side conversation parsing lives

§5.1 keeps `builder.ts` client-side and notes it would "later" be mirrored server-side for large
exports. Whether that mirror is a Ruby port, a Python sidecar, or a Node process invoked by the
engine is genuinely open, and it interacts with the provider-ingestion relocation in §9.1.

---

## 10. Cross-references

| Where | What |
|---|---|
| `docs/dockerization-strategy.md` | Compose-era topology and its blocker analysis — still accurate; this doc changes the deployment target, not the blockers |
| `docs/refactor/CLI-HEXAGON-USER-STORIES.md` | `SFL-CLI-*`, unified entry point with subcommands, replacing separate binstubs |
| `docs/refactor/EMBEDDING-HEXAGON-USER-STORIES.md` | `SFL-EMB-*`, authoritative over the rendered `.html` |
| `docs/refactor/INGEST-PARSER-HEXAGON-USER-STORIES.md` | `SFL-ING-*`, including the `POST /ingest` contract (SFL-ING-13) and `TargetResolver` (SFL-ING-19) |
| `docs/refactor/TOPIC-MODELING-HEXAGON-USER-STORIES.md` | `SFL-TOP-*`, BERTopic migration |
| sfl-engine `track-system-design-specs-1vhczyk` | Doc-vs-code verification; `Core::Registry` / `ClassificationRegistry` non-collision |
| SCC `track-integrating-sfl-engine-as-backend-for-syncopated-1da4gpp` | Client integration; `POST /ingest` contract accepted |
| SCC `track-dockerization-and-microservices-architecture-0f84yz9` | stdio sidecar + Podman Quadlets + shared volumes (accepted) |
| SCC `ROADMAP.md` | Phase 2 already frames sfl-engine as the backend |
| sfl-engine `track-ecosystem-architecture-engine-visual-driver-1odobii` | This doc's durable record on the sfl-engine side, including "SCC is a pluggable frontend, not the frontend" |
| SCC `track-ecosystem-architecture-engine-visual-driver-147ixsh` | This doc's durable record on the SCC side, including the §9.1/§9.2 resolutions |
| sfl-engine `track-cli-hexagon-unified-entry-point` | Unified `sfl-engine` executable with subcommands (SFL-CLI-*) |
| SCC `track-local-session-intelligence-search-retrieval-back-0qlgvlv` | Retired 2026-09-13 (§9.1) |
| SCC `track-local-session-intelligence-analysis-insights-eng-1bg9glv` | Relocated server-side 2026-09-13 (§9.1) |
