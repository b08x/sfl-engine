# SIFT System Design Assessment

**Assessment mode:** System Design Review  
**Assessment date:** 2026-08-02  
**Scope:** repository structure, composition roots, core pipeline, analysis engine, LLM wiring, storage/retrieval adapters, and HTTP API.

## Executive verdict

SFL Engine has a coherent ports-and-adapters shape with an explicit composition root, a reusable two-pass pipeline, source polymorphism, and infrastructure adapters behind constructor-injected collaborators. The architecture is suitable for continued development and controlled internal use.

It is not yet an unconditional production-ready design. The highest-risk gaps are transactional consistency in the review workflow, disclosure of internal exception messages through the API, and incomplete executable verification caused by a local Bundler/toolchain mismatch.

**System design score: 78/100 — Good, with moderate architectural improvements required.**

This is a design assessment, not a claim that all runtime checks passed. At assessment time, Bundler commands terminated before execution because the project requires Bundler `~> 2.6`, while the host exposed Bundler `2.5.22` and `4.0.3`.

## Architecture strengths

- `SFL::Boot` is the primary composition root and centralizes startup wiring.
- `Core::Pipeline` composes Pass 1, ideational extraction, Pass 2, persistence, and embedding through injected collaborators.
- `Analysis::Engine` provides one compile loop for conversation, documentation, and knowledge-base sources.
- `Core::Ports` and `Core::Ports::Null` provide explicit seams for storage, annotation, embedding, logging, caching, and instrumentation.
- `API::Server` receives an `API::Context` rather than constructing infrastructure inside route dispatch.
- `PgHybridRetriever` applies filters in both retrieval arms before candidate limiting, preserving selective results more reliably than post-filtering.

## Findings

### High priority

#### Review workflow needs an explicit transaction

**Claim:** Clause re-annotation and its audit record can become inconsistent if the second write fails.

**Data:** `API::Server#review_clause` may call `reannotate_clause` and then `record_review` (`lib/sfl/api/server.rb`). The inspected application flow does not show one transaction spanning both operations.

**Warrant:** A review decision is one domain operation. Its state mutation and audit event should commit or fail together.

**Remediation:** Introduce an application-level review service that performs re-annotation, persistence, and audit recording inside one database transaction. Add failure-path tests at each write boundary.

**Issue:** [#2](https://github.com/b08x/sfl-engine/issues/2)

#### Production API errors should not expose exception messages

**Claim:** The generic API error path leaks internal exception details.

**Data:** `API::Server#respond` returns `e.message` in the JSON response for unexpected exceptions (`lib/sfl/api/server.rb`).

**Warrant:** Database, provider, filesystem, and configuration details can be disclosed through exception text.

**Remediation:** Return a client-safe message and correlation ID; log structured exception context server-side. Permit detailed responses only in explicit development mode.

**Issue:** [#3](https://github.com/b08x/sfl-engine/issues/3)

### Medium priority

#### API route handlers carry application orchestration

`API::Server` combines Rack parsing, validation, use-case orchestration, persistence workflows, and serialization. Extract focused application services for compile, retrieve, synthesize, clause review, and review-queue decisions while leaving HTTP translation in the server adapter.

**Issue:** [#5](https://github.com/b08x/sfl-engine/issues/5)

#### `SFL::Boot` contains several policy domains

`SFL::Boot` owns environment loading, LLM task defaults, provider key requirements, RubyLLM configuration, tracing policy, database setup, and Pass 1 interpreter discovery. Retain `Boot.call` as the public entrypoint, but extract focused configuration resolvers as the system grows.

**Issue:** [#6](https://github.com/b08x/sfl-engine/issues/6)

#### API context constructs duplicate retrievers

`API.build_context` constructs equivalent hybrid retrievers for direct retrieval and synthesis. Reuse one instance unless separate retrieval configuration becomes intentional.

**Issue:** [#7](https://github.com/b08x/sfl-engine/issues/7)

### Low priority

#### Move migration-history commentary into decision records

Implementation comments should preserve current invariants; detailed legacy migration history and phase rationale belong in durable architecture documentation.

**Issue:** [#8](https://github.com/b08x/sfl-engine/issues/8)

#### Add architecture-level tests

Protect the intended dependency direction and composition graph with tests covering Zeitwerk eager loading, composition factories, port boundaries, and the absence of concrete infrastructure construction inside core use cases.

**Issue:** [#9](https://github.com/b08x/sfl-engine/issues/9)

## Recommended architectural direction

Keep the current core boundaries. Do not replace the architecture wholesale. The next hardening increment should be:

1. Create application services for review and other API workflows.
2. Make review state changes transactionally atomic.
3. Sanitize API error responses and add request correlation.
4. Narrow `Boot` into focused configuration resolvers without losing one startup entrypoint.
5. Add architecture tests before expanding the HTTP surface.
6. Resolve the Bundler constraint and rerun the full verification suite.

## Related documents

- [Project Overview](project-overview.md) — neutral current-system description
- [Architectural Lineage](architectural-lineage.md) — design origins and translations
- [LLM Role Isolation](use-cases/llm-role-isolation.md) — Rhetorical Firewall hypothesis
- [README](../README.md) — project entrypoint
- [GitHub issues](https://github.com/b08x/sfl-engine/issues) — actionable follow-up work
