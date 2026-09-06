# Shared Annotation Substrate — Design

**Date:** 2026-09-06
**Status:** Draft — pending user review
**Code lands in:** `/home/b08x/WorkspaceV3/sfl-engine` (service side), `/home/b08x/WorkspaceV3/Syncopated/phantom-agent` (client side)
**Related specs:** [Vault Annotation Substrate](2026-08-29-vault-annotation-substrate-design.md) — establishes "one substrate, two thin consumers" and explicitly defers "Agent chat / RAG Q&A over the vault" as future work for "a separate plugin later, built on this substrate's retrieval layer." This spec is that plugin's foundation, generalized beyond the vault to any consumer.
**Umbrella brand:** `syncopatedQi` — working name for the suite this belongs to (sfl-engine, phantom-agent, `syncopated-context-compiler`, `gitagent-workbench`). "Qi" quietly backronyms to "Quality Intelligence" — subtext, not something to foreground. Not exhaustively decided; recorded here so it isn't lost.

---

## Problem

Two independent implementations of the same idea exist today:

- **phantom-agent** (`src/phantom_agent/annotator/`) does SFL annotation in a single LLM
  call: raw chunk text in, asks the LLM to both segment into clauses *and* annotate
  them, `mood: str` stored with no validation, no `tenor`, no `modality_weight`, no
  annotation-source provenance. The resulting `sfl_metadata` JSONB column is written
  by the batch annotator and never read by anything in `search/` — stance-filtered
  retrieval is not implemented, only stored as inert data.
- **sfl-engine** implements the same idea properly: Pass 1 (`spacy_sidecar_parser.rb`,
  a long-lived subprocess speaking NDJSON over stdin/stdout) grounds Pass 2's LLM
  annotation with real POS/dependency/root-verb data; mood is canonicalized through
  `ClassificationRegistry` (Jaro-Winkler via `amatch`); `AnnotationSource` +
  `TRUSTED_ANNOTATION_SOURCES` give real provenance; `tenor_tracker.rb` exists.

Rather than backport sfl-engine's design into phantom-agent's Python codebase (or
worse, maintain both), consolidate: sfl-engine becomes the one annotation/retrieval
substrate, reachable as a service, and phantom-agent becomes a client of it.

## Non-goals (this spec)

- **Generalizing phantom-agent's ingestion into an arbitrary adapter/Source
  framework** (databases, Obsidian vaults, any document type). Deliberately deferred —
  this spec's interfaces must not foreclose it (see Future Work), but building it is a
  separate pass.
- **RDF/Turtle topic graph + GraphQL traversal.** Topics are a plain scalar column in
  this spec. Deferred, but the schema must not make adding graph edges later
  structurally painful.
- **Wiring `syncopated-context-compiler` or `gitagent-workbench` to the substrate.**
  Both are named consumers in Future Work; neither needs code changes for this spec to
  land, since they'd only need the HTTP/MCP endpoints this spec creates.
- **Tenant/agent-identity partitioning of stored data.** Considered and explicitly
  rejected: different agent profiles share the same topic-keyed context. Agent
  identity is not a partition key anywhere in this design.
- **Disk cleanup / auditing the ~90GB of demo and prototype projects.** Unrelated,
  destructive, and deserves its own task.

## Shape

```
phantom-agent (ingestion)  ─┐
Hermes-agent (future)       ├──HTTP/MCP──▶  sfl-api container (Roda routes + remote MCP)
other syncopatedQ agents   ─┘                       │
                                              same in-process
                                              Context/pipeline objects
                                                     │
                                       Pass 1 (spaCy, baked into image)
                                                     │
                                       Pass 2 (dspy LLM annotation)
                                                     │
                                         Postgres + pgvector (Quadlet volume)
```

One container image (Ruby + spaCy, per the existing `docker/api.Dockerfile` decision
to avoid a docker-socket-mounted sidecar), serving both HTTP and remote MCP from the
same in-process pipeline — no internal network hop between the two transports.

## Components

### 1. HTTP routing: Roda, still served by Falcon

`lib/sfl/api/server.rb` is currently a hand-rolled `Rack` `call(env)` implementation
routing `GET /health`, `POST /pipeline/compile`, `POST /clauses/:id/review`,
`GET/POST /review-queue*`, `GET /clauses/review-queue`, `POST /retrieve`,
`POST /synthesize` by hand. Replace it with a Roda app. Roda and Falcon are not
alternatives — Roda generates a Rack app, Falcon is the async-native server that runs
it — so `config.ru`'s `run SFL::API::Server.new(...)` line is unaffected in shape,
only in what `Server` is internally. `SFL::API::Context` (the pre-wired collaborator
struct) is reused as-is; only the routing layer changes.

### 2. Remote MCP server

A new `SFL::API::McpServer` (or similar), mounted in the same Rack app / served from
the same container, sharing `SFL::API::Context`'s already-constructed `pipeline`,
`retriever`, and `synthesizer` — no HTTP round-trip internally, since both are Ruby
objects in the same process. Exposes tools:

- `annotate(text)` → runs the clause through Pass 1 + Pass 2, returns ideational +
  interpersonal payloads with provenance.
- `retrieve_stance_filtered(query, filters)` → wraps `PgHybridRetriever` +
  `Retrieval::ContextSynthesizer`, applying interpersonal-payload filters before
  returning context — this is the part of the "Rhetorical Firewall" that was never
  wired up in phantom-agent (`sfl_metadata` written, never read).

Transport is **remote (HTTP/SSE)**, not stdio: Hermes-agent and other future
consumers are separately-deployed services, not local subprocesses this Ruby process
could spawn. stdio MCP remains an option for local dev workflows (e.g., adding it to
an editor's own MCP config while working in this repo) but is not the deployed shape.

### 3. Deployment: Podman Quadlets

```
~/.config/containers/systemd/
├── sfl-pgdata.volume        # named volume, survives container recreation
├── sfl.network              # postgres/api resolve each other by name
├── sfl-postgres.container   # pgvector/pgvector:0.8.6-pg16
└── sfl-api.container        # combined Ruby+spaCy image; Requires=/After=sfl-postgres.service
```

Migrations run as a one-shot unit (`Type=oneshot`, `ExecStartPre`, or a separate
`sfl-migrate.container`) — consistent with the existing "no auto-migration on boot"
decision recorded in `AGENTS.md`. Fresh-install bring-up: drop the four unit files,
`systemctl --user daemon-reload && systemctl --user start sfl-api.service`. No
existing Quadlet template exists elsewhere in the workspace to inherit from (checked
`omega-13`'s `quadlets-spacy-whisper` branch and `pop_os-workstation-builder`'s
tracked "quadlet ecosystem" work — neither has landed `.container`/`.volume` units);
this is the first one.

### 4. phantom-agent as client

`src/phantom_agent/annotator/extractor.py`, `models.py`, and `sfl_annotation.py` are
retired. `src/phantom_agent/ingestion/ingestion.py` calls the sfl-api HTTP endpoint
(`SFL_API_URL` env var) instead, sending raw chunk text and storing back the real
annotation the substrate returns. `analytics/topic_modeling.py` (BERTopic) is
untouched — it's a different technique than sfl-engine's `analysis/topic_modeler.rb`
(tomoto LDA/HDP), and reconciling the two topic-modeling approaches is out of scope
here.

## Data model

Storage stays keyed by **topic**, not by agent/tenant — this was explicitly decided
against multi-tenant partitioning. Existing `clauses` / `ideational_payloads` /
`interpersonal_payloads` tables are unchanged by this spec. The one constraint carried
forward from the "topics eventually become an RDF/Turtle graph" future-work item:
don't introduce anything that treats `topic` as an unindexed free-text blob only a
single owner writes to — a plain, shared, indexed scalar column is fine now; a
graph-valued topic later should be an additive migration, not a rewrite.

## Error handling

- Sidecar transport failures already have a crash-and-retry-once policy
  (`SpacySidecarParser#fail_or_retry`) — unchanged by this spec.
- HTTP/MCP callers (phantom-agent, future agents) must treat the substrate as a
  network dependency: annotation failures should not silently drop content the way
  `run_sfl_annotation`'s `except Exception` currently does in phantom-agent today —
  the client should surface/queue failures rather than skip silently. Concrete retry
  policy is an implementation detail for the plan, not fixed here.

## Testing

- sfl-engine side: existing spec suite (`classification_registry_spec.rb`,
  `engine_spec.rb`, `server_spec.rb`) covers Pass 1/Pass 2 and the current hand-rolled
  routing; routing tests get rewritten against Roda's app, not the underlying
  pipeline, which is untouched by this spec.
- New: MCP server tests (tool contracts, shared-Context wiring, retrieval filtering
  behavior).
- phantom-agent side: `tests/` gets an integration test replacing
  `annotator`-specific tests with client tests against a stubbed/local sfl-api.

## Future work (explicitly out of scope here, recorded so this spec doesn't box them out)

1. **Generalized adapter/Source layer** — phantom-agent's ingestion generalizes from
   skills-only to any document/database/vault, mirroring sfl-engine's existing
   `core/loaders/` pattern (Markdown/PDF/CSV/Canvas/Conversation Sources). Design for
   extensibility, not exhaustive source coverage.
2. **Topic graph (RDF/Turtle + GraphQL/SPARQL-style traversal)** — topics become
   navigable via edges between related topics, not just exact match.
3. **UX consumers** — `syncopated-context-compiler`'s existing "Multi-Source Import"
   and "3D Graph Visualization" features are natural front ends for #1 and #2
   respectively, once built. `gitagent-workbench`-authored agent profiles are the
   expected shape of "agent profile" in this substrate's shared-context model, once
   it's wired to call the substrate at all (it currently has no runtime coupling to
   either project). Noted for whoever picks this up: gitagent-workbench's underlying
   functionality is solid, but its UI needs real rework before it's worth building on
   — dense screens with horizontal scrollbars, and actions that navigate to a separate
   window instead of staying in place. Any future wiring work should budget for an
   interface pass, not just the integration itself.
4. **Umbrella naming pass** — `syncopatedQi` locked as working name; actual rename of
   individual repos (if any) is separate, low-priority, mechanical work.
