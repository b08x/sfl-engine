# SFL Engine

**Stance-Filtered RAG for LLM Security**

A Ruby application that hardens RAG pipelines against context poisoning by separating *what was said* from *how it was said* — then filtering the *how* before it reaches the LLM.

---

## The Problem

Standard RAG retrieves text by semantic similarity and hands it to the LLM as context. But language carries two simultaneous payloads:

- **Facticity** — what happened, who did what to whom
- **Interpretation** — the persuasion, emotion, and rhetorical stance wrapped around those facts

A clause like *"Everyone agrees this migration is catastrophic!"* contains a factual claim (migration status) wrapped in a persuasive frame (social proof, hyperbolic modality, declarative pressure). Standard RAG sees them as one indivisible string. The LLM absorbs the stance along with the facts.

Prompt-level defenses ("don't be manipulated") fail because they compete with adversarial content on the same channel. The defense must be structural.

## The Architectural Insight

A useful way to understand the problem is through separation of concerns. Standard RAG treats human language as one fused retrieval object: factual content and rhetorical stance share the same text, embedding, and context channel. That makes it difficult to apply a policy to *how* something was said without discarding *what* was said.

SFL Engine applies an MVC-like separation at the data layer:

- **Ideational payload** — the Model-like representation of processes, participants, and circumstances: what happened.
- **Interpersonal payload** — the View-like representation of mood, modality, tenor, and attitude: how the claim is presented.

The analogy is architectural, not literal. Interpersonal metadata is not merely decorative presentation; it is a security-relevant signal used by retrieval policy. Separating the payloads lets the system filter rhetorical characteristics before synthesis while preserving the underlying clause content for inspection and citation.

This is closer to input sanitization than to `eval()` prevention in a direct technical sense: the system attempts to remove or constrain a class of influence-bearing metadata before it reaches the model. It does not make text safe automatically, prove that a clause is malicious, or guarantee that an LLM will ignore every persuasive cue. Those claims require adversarial evaluation and outcome studies that have not yet been completed.

## Architectural Evaluation: Comparative Perspectives

The design is best understood by contrasting the coupled architecture of standard RAG with SFL Engine's decoupled architecture.

### Standard RAG: The Coupled Paradigm

Traditional RAG pipelines embed raw text into dense vectors, fusing factual content and rhetorical stance into one latent retrieval space. When the LLM receives the retrieved text, it encounters the fact and its emotional or persuasive framing simultaneously.

This coupling creates a context-poisoning risk. Prompt-level instructions such as “ignore manipulative tone” must compete with adversarial text in the same input channel. The instruction is behavioral and generic; the retrieved content can carry concrete social-proof, urgency, certainty, or authority cues that influence how the model interprets the underlying claim.

### SFL Engine: The Decoupled Paradigm

SFL Engine separates fact from interpretation at the data-storage layer. Ideational payloads represent processes, participants, and circumstances; interpersonal payloads represent mood, modality, tenor, and attitude. Retrieval policy can then constrain the interpersonal metadata before synthesis while retaining the ideational content as inspectable evidence.

This is the architectural basis of the **Rhetorical Firewall**: not a claim that manipulation is magically removed, but a deterministic boundary that prevents rhetorical metadata from being treated as inseparable factual context. The synthesis stage receives labeled fields and must evaluate facticity separately from the stance associated with its source text.

The phrase “sterile vacuum” should be read as a design goal, not a proven runtime condition. The LLM still receives text and metadata, and the effectiveness of the separation depends on annotation quality, filter policy, prompt construction, and model behavior. Empirical testing must establish whether this decoupling reduces stance absorption in practice.

## The Architecture

SFL Engine implements a two-pass annotation pipeline that extracts linguistic metadata and separates it into independently filterable payloads:

```
Input → Pass 1 (spaCy) → Pass 2 (LLM) → Store (Postgres + pgvector)
                         ↓
                   Ideational Payload    → facts, process types, participants
                   Interpersonal Payload → mood, modality, tenor, attitude
                         ↓
                   Retrieve (RRF + Scalar Stance Filters)
                         ↓
                   LLM receives: facts without persuasion
```

**Pass 1** (spaCy subprocess sidecar): Syntactic parsing. Extracts clause boundaries, process types (material, mental, relational, verbal, behavioral, existential), participants, and circumstances. Rule-based, deterministic, fast.

**Pass 2** (LLM via dspy.rb): Semantic annotation. Classifies mood (declarative, interrogative, imperative, exclamative), modality weight (0–1 certainty scalar), tenor (formality register), and speaker attitude (social proof, authority, emotional, neutral). Model-configurable per task.

**Storage** (Postgres + pgvector): Ideational and interpersonal payloads live in separate tables. Independently indexable. Independently filterable.

**Retrieval** (HybridRetriever): Reciprocal Rank Fusion merges vector similarity and keyword search. Then scalar stance filters exclude clauses whose interpersonal profile matches structural fingerprints of cognitive distortion — *before* the LLM's context window is assembled.

## The Intellectual Lineage

This is not a single-discipline design. It is a composite architecture synthesizing patterns from domains that usually do not interact:

| Domain | Pattern | Engineering Translation |
|--------|---------|------------------------|
| **Systemic Functional Linguistics** | Three metafunctions (ideational, interpersonal, textual) | Extractable JSON metadata per clause |
| **Cognitive Behavioral Therapy** | Cognitive distortions as structural linguistic patterns | Scalar stance filters on interpersonal payloads |
| **Cognitive Neuroscience** | Working memory consolidation | Rolling Synthesis — compress context, preserve gist |
| **Existential Philosophy** | Facticity vs. interpretation | Payload separation — facts and stance in separate tables |
| **Unix Philosophy** | Composable, single-purpose tools | Two-pass pipeline with Dry::Struct type contracts |
| **Cybersecurity** | Air gapping, data sanitization | Rhetorical Firewall — filter before the context window |

No single domain solves the problem. SFL provides the metadata. CBT provides the distortion taxonomy. Neuroscience provides the consolidation pattern. Philosophy provides the facticity/interpretation distinction. Unix provides the composability. Cybersecurity provides the air-gapping model. The synthesis is what makes the system novel; the individual threads are what make it trustworthy.

## Directory Layout

```
lib/sfl/
├── core/      # types, ports, pass1 sidecar client, pass2 engine, pipeline, loaders
├── store/     # Sequel/pg/pgvector: repositories, migrations, retrieval
├── llm/       # dspy.rb + dspy-signature annotators, per-task model/provider config
├── prompts/   # plain folder of prompt templates
├── cli/       # non-interactive/scriptable analyzer commands
├── gui/       # glimmer-dsl-libui desktop GUI (opt-in require)
└── chat/      # interactive chatbot agent (RubyLLM::Tool wrappers)
```

One Zeitwerk loader rooted at `lib/` (see `lib/sfl.rb`). `experiments/` is quarantined — never autoloaded, never shipped.

## Getting Started

```bash
# Prerequisites
docker compose up -d          # Postgres (port 5433) + Redis (port 6380)
bin/setup-python              # vendor spaCy into .sfl-python/
bin/setup-config              # interactive .env setup

# Run
rake db:migrate               # apply Sequel migrations (manual — no auto-migrate)
bundle exec rake              # full verification (spec + rubocop)

# Analyze
bundle exec exe/sfl-analyze conversation input.jsonl --store
bundle exec exe/sfl-analyze documentation ./docs/ --store
bundle exec exe/sfl-analyze context "what happened?" --limit 10
```

Not `bundle exec sfl-analyze` (a bare command name) — this is a non-gem
application (no gemspec/`executables` list, see Key Design Decisions), so
there is no Bundler-generated binstub to resolve that name to. Run the
`exe/` script directly.

### Server

```bash
bundle exec exe/sfl-api                 # Falcon on 0.0.0.0:3001 (default)
PORT=3002 bundle exec exe/sfl-api       # custom port
HOST=localhost bundle exec exe/sfl-api  # bare-metal-only, loopback bind
```

Or containerized (see `docs/dockerization-strategy.md`):

```bash
docker compose --profile app build api
docker compose --profile app up -d api        # api service
docker compose --profile app run --rm migrate # one-shot db:migrate
```

`api`/`migrate` sit behind the `"app"` Compose profile — plain `docker
compose up -d` (no `--profile`) still starts only postgres/redis, unchanged.

## CLI

```
sfl-analyze <subcommand> <input> [options]

Subcommands:
  conversation <input>       Analyze JSONL conversations or subtitle files
  documentation <path>       Analyze markdown/PDF files
  knowledge-base <path>      Assess a KB directory for migration
  context "<query>"          Query stored clauses, synthesize an answer

Options:
  --pass1-only               Skip LLM annotation (placeholder values)
  --store                    Persist clauses + embeddings
  --resume                   Reuse cached Pass 2 results
  --disable-tracing          Skip OpenTelemetry/Langfuse setup
  --narrative                Also generate narrative_report.md
```

Invoke as `bundle exec exe/sfl-analyze ...` (see note above).

## LLM Configuration

Per-task provider/model via ENV:

| Task | ENV Prefix | Default |
|------|-----------|---------|
| Pass 2 annotation | `SFL_TASK_PASS_TWO_ANNOTATION_` | openrouter/mistralai/mistral-small-3.2-24b-instruct |
| Batch annotation | `SFL_TASK_PASS_TWO_BATCH_ANNOTATION_` | openrouter/mistralai/mistral-small-3.2-24b-instruct |
| Context synthesis | `SFL_TASK_CONTEXT_SYNTHESIS_` | inherits from pass_two_annotation |
| Embedding | `SFL_TASK_EMBEDDING_` | ollama/embeddinggemma:latest |

## Key Design Decisions

- **No auto-migration**: Boot never runs migrations. `rake db:migrate` is explicit.
- **Subprocess sidecar**: Pass 1 is a spaCy subprocess, not in-process Python. No PyCall, no GIL, no require-time ENV mutation.
- **Constructor injection everywhere**: `SFL::Boot` is the sole ENV reader. Everything else takes config via kwargs.
- **Null objects**: `Core::Ports::Null::*` provides no-op implementations for disabled features.
- **Payload separation**: Ideational and interpersonal metadata in separate tables. Never fused at storage time.

## Current status

Phases 0–5 of the rebuild blueprint are implemented: the two-pass pipeline, Postgres/pgvector storage, hybrid retrieval, unified analysis engine, formatters, boot composition root, embedder, CLI, and HTTP API. The system design was assessed with the SIFT protocol at **78/100** (suitable for continued development and controlled internal use, not yet an unconditional production-ready system) — see [SIFT System Design Assessment](docs/sift-system-design-assessment.md).

All P0 (blocking/security/data-integrity) issues from that assessment are now fixed and closed: clause re-annotation and review-audit recording are transactionally atomic (`API::ClauseReviewService`), unexpected API errors are sanitized before reaching clients (a generic response + logged `request_id`, raw detail opt-in only via `SFL_API_DEBUG_ERRORS`), the toolchain is pinned and reproducible (Ruby 4.0.1 via `.tool-versions`), Docker Compose auto-start is opt-in (`SFL_AUTO_START_DOCKER=1`) rather than unconditional, the API binds `0.0.0.0` and its CORS origins are env-configurable for containerized deployment, and `sfl-api` now runs as a proper container (`docker/api.Dockerfile`, spaCy baked in) — see `docs/dockerization-strategy.md`.

Remaining recommendations from the assessment cover extracting API route orchestration into application services, decomposing `SFL::Boot` configuration policy, adding architecture-level dependency tests, reusing the API hybrid retriever, and moving migration-history commentary into decision records. See the [GitHub issue backlog](https://github.com/b08x/sfl-engine/issues).

This remains infrastructure and a research-oriented engineering artifact, not a validated outcome study. No external corpus has yet established that stance filtering improves LLM reasoning outcomes or adversarial robustness.

## Related

- [Architectural Lineage](docs/architectural-lineage.md) — the intellectual foundations
- [SIFT System Design Assessment](docs/sift-system-design-assessment.md)
- [GEB Lens on SFL Engine](docs/geb-lens-on-sfl-engine.md) — Hofstadter's formal systems applied to the two-pass architecture
- [Pedagogy Case Study](docs/pedagogy-case-study.md) — human-AI dialogue analysis instrument
- [LLM Role Isolation](docs/use-cases/llm-role-isolation.md) — the Rhetorical Firewall hypothesis
- [ROADMAP](ROADMAP.md) — Rolling Synthesis, Cognitive Gas, Semantic Convergence
