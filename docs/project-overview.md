# SFL Engine — Project Overview

**What this document is for**: a single, neutral, comprehensive description of what
the SFL Engine actually is and does — not angled toward any one audience. It
exists so other documents (a UI design brief, an academic case study, a portfolio
write-up, a future demo) can all be generated *from* this one, rather than each
re-describing the project from scratch and drifting apart. If you're pointing an
external tool (a design assistant, an editor, a reader who's never seen this
codebase) at the project, start here.

## What it is, in one paragraph

The SFL Engine is a Ruby application that analyzes text — conversations,
documentation, or general knowledge-base corpora — by annotating every clause
with a full Systemic Functional Linguistics (SFL) breakdown: what happened
(Ideational: process type, participants, circumstances), the stance being taken
(Interpersonal: mood, epistemic certainty, formality), and how the message coheres
as text (Textual). It combines a deterministic syntactic parse (spaCy, via a
subprocess sidecar) with LLM-based interpretation of stance and certainty,
persists the result to Postgres with vector embeddings for hybrid retrieval, and
exposes the whole thing through both a CLI and an HTTP API. It is mid-rebuild
(`sfl-engine`, a from-scratch architectural rewrite of an earlier working
version, `sfl-compiler`) — Phases 0-5 of a 6-phase blueprint are done; only
hardening (performance validation, documentation, coverage) remains.

## The two-pass pipeline

**Pass 1 — syntax (deterministic, no LLM)**: a Python spaCy sidecar process
receives raw text over a line-delimited JSON protocol and returns, per sentence,
every token's text, lemma, part-of-speech, and dependency relation to its head —
addressed by token position, not text, so repeated words never collide. This
produces a real dependency tree, not a bag of tokens with tags. A rule-based
`IdeationalExtractor` then maps those dependency labels (`nsubj`, `dobj`, `pobj`,
`xcomp`...) onto SFL's Ideational categories: process type (material, mental,
relational, verbal) and participant roles (Actor, Goal, Recipient, Circumstance).

**Pass 2 — stance (LLM-based)**: an LLM annotator takes the syntactic clause plus
its Ideational payload and produces the Interpersonal payload: mood
(declarative/interrogative/imperative), a continuous modality weight (0.0-1.0,
epistemic certainty), a continuous tenor value (0.0-1.0, formality/social
distance), speaker attitude, a reasoning string, and — for annotations worth
auditing — a structured reasoning trace (premises, inference rule, conclusion,
confidence, and a SHA-256 hash over all three for reproducibility).

Every clause that passes through both stages becomes an `AnnotatedClause`: one
object carrying its own syntax, its own Ideational payload, and its own
Interpersonal payload, permanently linked by a single id.

## Three kinds of input, one pipeline

The system doesn't only analyze conversations. `lib/sfl/analysis/` has three
source types sharing one compile loop (`Analysis::Engine`):

- **ConversationSource** — turn-by-turn dialogue. Loaders exist for ChatGPT
  exports, Claude.ai exports, and generic chat formats, each normalizing into the
  same per-turn `Types::Unit` shape regardless of origin.
- **DocumentationSource** — markdown, PDF, and similar prose corpora, chunked and
  analyzed the same way.
- **KnowledgeBaseSource** — a directory or file set treated as a knowledge base:
  each section becomes a `KnowledgeArtifact` with a content-type classification,
  a quality score, and a migration-action recommendation (keep/update/archive),
  rolled up into a `KnowledgeBaseReport`.

All three produce `AnnotatedClause`s through the same Pass 1/Pass 2 pipeline; only
what counts as a "unit" and how results get packaged differs.

## Conversation-level aggregation

Beyond per-clause annotation, the system computes conversation-level structure:

- **`SpeakerProfile`** (per speaker, per conversation): turn count, average tenor,
  tenor range and variance, average modality, mood distribution, dominant process
  types.
- **`KeyMoment`** (per conversation): automatically flagged inflection points —
  `tenor_shift`, `modality_shift`, `topic_shift`, `semantic_anomaly`,
  `deflation_anomaly` — each with a magnitude and a description.

This is the layer that turns "here's what one sentence means" into "here's how
this exchange evolved" — register shifts, confidence drops, topic pivots, all
detected structurally rather than by keyword.

## Storage, retrieval, and human review

- **Storage**: Postgres. `PgClauseStore` is the single write path
  (`replace_document`: delete-then-insert per document, one transaction, so a
  re-run of the same document never leaves stale rows). Foreign-key cascades
  clean up dependent payload rows automatically.
- **Retrieval**: `PgHybridRetriever` combines semantic search (pgvector
  embeddings) and keyword search (Postgres full-text) via reciprocal rank fusion,
  with the SFL scalar fields (mood, tenor, modality, process type, source type)
  usable as hard filters — retrieval that can be constrained not just by topic
  but by *how* something was said.
- **Synthesis**: `ContextSynthesizer` answers a natural-language query by
  retrieving evidence clauses and asking an LLM to compose a cited answer,
  degrading gracefully (returns raw evidence, not a fabricated answer) when
  citation grounding fails.
- **Human-in-the-loop review**: two independent review queues. A *content*
  review queue (`PgReviewQueueRepository`) catches untrustworthy source text
  before it's ever compiled (a vision model's image description, a low-quality
  transcript). An *annotation* review queue (`PgAnnotationReviewRepository`)
  catches low-confidence Pass 2 output after compilation, with accept/reject/
  re-annotate decisions recorded as a permanent, append-only audit trail — a
  human's decision is never silently overwritten by a later re-annotation.

## Interfaces

- **CLI** (`exe/sfl-analyze`): four subcommands — `conversation`,
  `documentation`, `knowledge-base`, `context` — each a thin argv-parsing layer
  over the same Boot/Pipeline/Engine collaborators.
- **HTTP API** (`exe/sfl-api`, `lib/sfl/api/`): a Rack application exposing the
  same collaborators over HTTP —

  | Route | Purpose |
  |---|---|
  | `GET /health` | liveness check |
  | `POST /pipeline/compile` | compile raw text into annotated clauses (sync) |
  | `POST /retrieve` | hybrid search with SFL scalar filters |
  | `POST /synthesize` | cited, LLM-composed answer to a query |
  | `GET /clauses` | filtered, paginated corpus browse |
  | `GET /clauses/review-queue` | annotation-confidence review queue |
  | `POST /clauses/:id/review` | accept/reject/re-annotate a clause |
  | `GET /review-queue` | content-review queue |
  | `POST /review-queue/:id/decide` | approve/edit/reject pre-compile content |

  This is the surface a browser UI would sit on top of — every route above maps
  to exactly one screen's worth of functionality (see below).

## Current status (verified against source and git history, not assumed)

Phases 0-5 of the rebuild blueprint are complete: full pipeline, Postgres/pgvector
store with hybrid retrieval, unified analysis engine across all three source
types, formatters, a real embedder, the CLI, and the HTTP API described above.
655 specs passing, RuboCop clean. Only Phase 6 (hardening — a measured performance
pass, a coverage gate, YARD documentation on the public API) remains before the
blueprint's own stated end state: installable, runnable, no scaffolding debt.

**What has not happened yet, stated plainly**: no external corpus has been run
through this system for any purpose — pedagogical, research, or otherwise. No
findings exist. This document describes working infrastructure, not a study.

## Why this project is reusable as a reference, beyond any one pitch

The system's actual capabilities span several distinct framings that don't
depend on each other:

- **A working infrastructure engineering artifact** — 23 years of Linux/infra
  background applied to a from-scratch-rebuilt service with a documented SIFT
  audit, a phased rebuild blueprint, ports-and-adapters architecture, a real
  subprocess boundary for the Python dependency, and a deployable HTTP surface.
  Relevant to infrastructure/platform-engineering conversations independent of
  the linguistics angle entirely.
- **A linguistically-grounded alternative to sentiment analysis** for anyone
  analyzing human-AI dialogue, tutoring transcripts, or support conversations —
  relevant to the pedagogy CFP, but not exclusive to it; the same instrument
  applies to customer-support QA, therapy-adjacent chat products, or any domain
  where *how* something was said matters as much as *what*.
- **A knowledge-base staleness/quality triage tool** — `KnowledgeBaseSource`
  produces a content-type classification, a quality score, and a
  keep/update/archive recommendation per document section, independent of any
  dialogue or linguistics framing — relevant to internal-docs, DevRel, or
  knowledge-management use cases with no dialogue angle at all.
- **A demo-ready subject for a browser UI** — every capability above already has
  an HTTP route; a frontend is the natural next artifact, and one already has a
  design brief drafted (see the prior Claude Design prompt covering a Corpus
  Browser, both review queues, and a Query Console).

Point any of these framings at this document for grounding rather than
re-deriving the project's capabilities from scratch each time.
