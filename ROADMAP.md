# SFL Engine — Roadmap

**Status:** Active
**Parent:** [README](README.md)

---

## Current State

Phases 0–5 of the rebuild are complete. The system has:

- Full two-pass pipeline (spaCy sidecar + LLM annotation)
- Postgres/pgvector store with hybrid retrieval
- Unified analysis engine across three source types
- CLI and HTTP API
- 655 specs passing, RuboCop clean

**What remains**: Phase 6 (hardening) and forward-looking research.

---

## Phase 6 — Hardening (≈ 3-4 days)

The final phase before the system is considered production-ready.

### Performance Validation
- Profile the full pipeline with the bench harness
- Identify bottlenecks in Pass 1 (spaCy sidecar IPC), Pass 2 (LLM calls), and storage (Postgres writes)
- Keep optimizations that show ≥10-20% wins; revert the rest
- Document performance characteristics in YAML records

### Coverage Gate
- Set coverage baseline at Phase 0 levels + 10 points
- Enforce in CI: specs must pass, RuboCop must be clean, coverage must meet threshold
- Branch coverage enabled (already configured in spec_helper.rb)

### YARD Documentation
- Public API surfaces: ports, engine, stores, CLI
- Public = commitment; everything else `private` by default
- Document constructor signatures, return types, and behavioral contracts

---

## Phase 7 — Modular Middleware (Future)

Transform the SFL Engine from a standalone application into a reusable
middleware layer that any RAG pipeline can adopt.

### Core Separation
Split the monolith into independent, installable components:

```
sfl-core      # Types, ports, pipeline, Pass 1 sidecar
sfl-store     # Sequel/pg/pgvector repositories
sfl-llm       # ruby_llm annotators, per-task config
sfl-cli       # CLI entry points
```

Each component has its own Gemfile, its own test suite, and no
cross-dependencies beyond the shared type contracts.

### Middleware Interface
Define a clean API for integration with existing RAG pipelines:

```ruby
# Annotate documents before storage
annotated = SFL::Core::Pipeline.new(...).compile(document)

# Filter during retrieval
results = SFL::Store::PgHybridRetriever.new(...).retrieve(
  query,
  filters: { min_tenor: 0.6, min_modality: 0.7 }
)

# Synthesize with labeled fields
answer = SFL::Analysis::ContextSynthesizer.new(...).synthesize(query)
```

### Adapter Layer
Support multiple vector databases and LLM providers without coupling:

- **Vector stores**: pgvector (current), Pinecone, Weaviate, Qdrant
- **LLM providers**: OpenRouter (current), OpenAI, Anthropic, local models
- **Document formats**: JSONL, Markdown, PDF, subtitles (SRT/VTT/ASS)

---

## Phase 8 — Rolling Synthesis (Research)

Implement neural memory consolidation for arbitrarily large documents.

### The Problem
Current retrieval operates on individual clauses. For long documents
(10,000+ words), the context window fills with raw clauses before the LLM
can synthesize a coherent answer. Truncation discards information
arbitrarily; consolidation preserves semantic gist.

### The Solution
Intermediate syntheses at semantic boundaries:

1. Process clauses in batches
2. At semantic boundaries (topic shifts, speaker changes, chapter breaks),
   synthesize the batch into a compact summary
3. Preserve SFL metadata (process types, modality, tenor) in the summary
4. Discard raw clause text; keep only the summary and the original clauses
   in Postgres for audit
5. Continue processing with the summary as working memory

### Expected Outcome
- Reasoning quality at cycle N+100 matches cycle 1
- Context window carries compressed summaries, not raw tokens
- Raw clauses remain in Postgres for human review and audit

---

## Phase 9 — Cognitive Gas (Research)

A resource-management mechanism for LLM calls.

### The Problem
Unbounded LLM calls during Pass 2 can exhaust API budgets, hit rate limits,
or produce diminishing returns on low-value clauses.

### The Solution
A "cognitive gas" budget that allocates LLM calls based on clause value:

- **High-value clauses** (novel information, high modality, complex syntax)
  get full LLM annotation
- **Low-value clauses** (repetitive, simple, low-information) get rule-based
  fallback or null annotation
- Budget exhaustion triggers graceful degradation: switch to Pass 1 only,
  or annotate only high-value clauses

### Expected Outcome
- Predictable API costs
- Graceful degradation under budget pressure
- No silent failures; budget status visible in pipeline output

---

## Phase 10 — Semantic Convergence (Research)

Detect when multiple clauses express the same semantic content in different
forms.

### The Problem
Conversations and documents often repeat the same idea with different
wording. Retrieval returns multiple redundant clauses, wasting context
window space and diluting the LLM's attention.

### The Solution
Compute semantic convergence scores between clauses:

1. Embed clause ideational payloads (process type + participants)
2. Cluster by embedding similarity
3. Within each cluster, select the clause with the highest interpersonal
   quality (modality, tenor) as the representative
4. Retrieve only representatives; discard redundant clauses

### Expected Outcome
- Higher information density in context window
- Reduced redundancy in retrieval results
- Better LLM reasoning (less noise, more signal)

---

## Related

- [README](README.md) — project overview and current status
- [rebuild-blueprint-with-plugin.md](rebuild-blueprint-with-plugin.md) — full SIFT audit and phased backlog
- [docs/architectural-lineage.md](docs/architectural-lineage.md) — intellectual foundations
