# Architectural Lineage: A Composite Design

**Status:** Design Documentation — SIFT-reviewed  
**Parent:** [README — Current status](../README.md)  
**Assessment:** [SIFT System Design Assessment](sift-system-design-assessment.md)

---

## Premise

This project is not the product of a single discipline. It is a composite
architecture — a system built by reverse-engineering and synthesizing design
patterns from a radically diverse array of research domains that usually do
not interact.

Linguistics does not talk to cybersecurity. Cognitive neuroscience does not
talk to existential philosophy. CBT does not talk to Unix. The SFL Engine
is built on the conviction that the intersection of these fields — the
territory none of them individually claim — is where the hard problem of LLM
security lives.

This document is transparent about the lineage. Every engineering pattern in
the engine traces back to a specific intellectual tradition. The synthesis is
what makes the system novel; the individual threads are what make it
trustworthy.

---

## Systemic Functional Linguistics (SFL)

### Origin

Michael Halliday's SFL — developed from the 1960s onward — treats language as
a system of choices. Every clause carries three simultaneous meanings, what
Halliday called **metafunctions**:

- **Ideational**: what is happening, who did what to whom.
- **Interpersonal**: the speaker's stance, mood, certainty, formality.
- **Textual**: how the clause is organized, what is given prominence.

### Engineering Translation

The engine reverse-engineers Halliday's metafunctions into programmatic,
extractable JSON metadata. Instead of using SFL as an analytical framework
for human reading, it uses SFL as a feature extraction schema for machine
retrieval.

The `IdeationalExtractor` (Pass 1, rule-based) classifies each clause's
process type — material, mental, relational, verbal, behavioral,
existential — using lemma-based verb lists. The `LLM::EngineBuilder` (Pass 2,
LLM-based) annotates each clause's interpersonal features: mood, modality
weight, tenor, speaker attitude.

The key engineering move is **payload separation**. SFL
metafunctions do not share a table. Ideational content lives in
`ideational_payloads`. Interpersonal content lives in
`interpersonal_payloads`. They are independently indexable and independently
filterable. This separation — facts in one table, tone in another — is the
structural foundation of the entire Safe RAG hypothesis.

### What It Gives the System

The ability to ask not just "what is this text about?" but "how was this text
said?" — and to filter on the answer. No other RAG retrieval system indexes
rhetorical stance as a first-class, scalar-filterable metadata dimension.

---

## Cognitive Behavioral Therapy (CBT)

### Origin

CBT, developed by Aaron Beck in the 1960s, identifies **cognitive
distortions** — systematic patterns of biased thinking that distort reality.
Emotional reasoning ("I feel it, therefore it is true"), hyperbolic extremes
("everything is always broken"), and mind reading ("everyone knows this is
wrong") are not just bad arguments; they are recognizable, classifiable
linguistic patterns with structural fingerprints.

### Engineering Translation

The engine borrows the practice of identifying cognitive distortions and
applies it programmatically via **stance filtering**. During RAG retrieval,
the `PgHybridRetriever` applies scalar filters on the interpersonal payload:

- High `min_modality` excludes hedged, uncertain, or speculative text —
  filtering out what CBT would call "catastrophizing" or "emotional
  reasoning."
- High `min_tenor` excludes informal, emotionally charged, or colloquial
  register — filtering out what CBT would call "hyperbolic extremes" or
  "personalization."
- Mood filtering can exclude exclamative or imperative clauses that
  pressure the reader — the linguistic form of "should statements" and
  "labeling."

The system does not diagnose cognitive distortions. It detects their
structural fingerprints — the linguistic texture that distorted thinking
leaves in language — and excludes them from the LLM's context window before
the model ever sees them.

### What It Gives the System

A programmatic defense against manipulative text that works without
understanding the text's content. The filters operate on metadata, not on
semantics. A document that says "Everyone agrees this is catastrophic!" is
excluded not because the system disagrees with the claim, but because the
clause's interpersonal profile — low tenor, social-proof modality,
declarative pressure — matches the structural fingerprint of a cognitive
distortion.

See [docs/use-cases/llm-role-isolation.md](use-cases/llm-role-isolation.md)
for the full attack vector and defense hypothesis.

---

## Cognitive Neuroscience

### Origin

Human working memory is bounded. George Miller's "magical number seven,
plus or minus two" established that humans can hold approximately 7±2
items in active memory at once. The brain does not respond to this limit by
attempting to hold more items; it responds by **consolidating** —
compressing short-term memory into long-term semantic memory during sleep
and rest, preserving the gist while discarding the raw sensory detail.

### Engineering Translation

The engine's **Rolling Synthesis** pattern mimics neural memory
consolidation. Instead of forcing an LLM to hold infinite tokens in its
context window — which degrades reasoning quality as the window grows — the
system periodically compresses short-term raw text into dense, long-term
"Axiomatic" semantic summaries.

The mechanism: intermediate syntheses fire at semantic boundaries. Each
synthesis compresses the working memory of clauses processed so far into a
compact summary that preserves SFL metadata (process types, modality weights,
tenor scores) but discards raw token sequences. The raw clauses remain in
PostgreSQL; the context window carries only the summary forward.

This is not truncation. Truncation discards information arbitrarily.
Consolidation discards raw detail while preserving semantic gist — the same
compression the brain performs when it converts a day's worth of
conversation into a single remembered insight.

### What It Gives the System

The ability to process arbitrarily large documents — 10,000-word incident
reports, multi-day conversation trees — without the context window degrading
into noise. The reasoning quality at cycle N+100 matches the reasoning
quality at cycle 1, because each cycle starts from a compressed semantic
summary, not from an ever-growing pile of raw tokens.

---

## Existential Philosophy

### Origin

Jean-Paul Sartre distinguished between **facticity** (the objective givens
of a situation — the facts that cannot be changed) and **interpretation**
(the meaning, narrative, or subjective stance imposed on those facts). A
situation is never just its facts; it is always facts-plus-a-story-about-
the-facts. But the facts and the story are separable — they are not the
same thing, even though they are experienced as a unity in natural
language.

### Engineering Translation

The engine physically separates the **ideational payload** (facticity —
what is happening, the objective content of the clause) from the
**interpersonal payload** (the imposed narrative — the persuasion, emotion,
and subjective stance). These live in separate database tables with separate
indices. They are never fused at storage time.

During retrieval and synthesis, the `ContextSynthesizer` presents these as
labeled, separable fields rather than fused prose. The LLM receives the
ideational content (the sterile existence of a request) and the
interpersonal metadata (the persuasive essence applied by the user) as
distinct inputs, not as a single indivisible string.

This forces the LLM to evaluate facticity in isolation from interpretation
— the same separation that existential philosophy asks humans to practice.
The model sees "material process; participants: migration, failure;
circumstances: current state" alongside "mood: declarative; modality:
0.85; tenor: 0.3; attitude: social_proof" — not "Every expert agrees the
migration is failing!" The first representation gives the model a fact to
evaluate. The second gives it a stance to adopt.

### What It Gives the System

The structural mechanism for de-fanging parahuman manipulation. By
separating facticity from interpretation at the data layer — not at the
prompt layer, not as a post-hoc instruction, but in the physical storage
schema — the system makes it structurally difficult for the LLM to
conflate "what was said" with "how it was said." The model must work to
reconstruct the fused meaning from labeled fields, and the evidence
suggests that this extra step is enough to prevent the automatic stance
absorption that standard RAG suffers from.

See [docs/use-cases/llm-role-isolation.md](use-cases/llm-role-isolation.md)
for the full hypothesis.

---

## The Unix Philosophy

### Origin

Doug McIlroy's original Unix principle: "Do one thing and do it well."
Programs should be small, composable, and communicate through clean,
standardized data formats. Complex systems are built by piping simple
programs together, each handling one stage of a transformation.

### Engineering Translation

The **Two-Pass architecture** is a Unix pipe with type safety. Pass 1
(spaCy sidecar) does one thing: syntactic parsing. It produces
`SyntacticClause` and `IdeationalPayload` objects — clean, standardized
data structures that pass down the pipe. Pass 2 (LLM via ruby_llm) does one
thing: semantic annotation. It consumes Pass 1's output and produces
`AnnotatedClause` objects. The two passes do not share state, do not call
each other, and can be run independently.

The pipeline enforces this separation with `Dry::Struct` type contracts
(see `lib/sfl/core/types/`) — the "velvet rope" that validates every
payload at the boundary between stages. A malformed Pass 1 output cannot
silently corrupt Pass 2; the type system rejects it at the door.

This extends to the analysis layer: `Analysis::Engine`,
`Analysis::ConversationSource`, `Analysis::DocumentationSource`, and
`Analysis::KnowledgeBaseSource` are independent modules that consume the
pipeline's output and produce their own. None of them touch `ENV`, none of
them print, none of them call each other directly. They are composable Unix
tools with injected dependencies, designed to back a CLI today and a web UI
tomorrow without modification.

### What It Gives the System

A pipeline where each stage can be tested, cached, replaced, and scaled
independently. Pass 1 can run without Pass 2 (`--pass1-only`). Pass 2 can
resume from a cached Pass 1 result without re-running the syntactic parse.
The analysis layer can be swapped for a different front end without
touching the pipeline. The Unix principle of composability is what makes
the system extensible — and what makes future phases tractable rather than
a rewrite.

---

## Cybersecurity

### Origin

Two concepts from information security practice:

- **Air Gapping**: physically isolating a critical system from untrusted
  networks so that no data can cross the boundary without explicit,
  controlled transfer.
- **Data Sanitization**: stripping untrusted input of potentially harmful
  content before it enters a trusted system — not trusting the input to
  behave, but structurally preventing it from carrying harm.

### Engineering Translation

The engine adapts air gapping and data sanitization to **semantic context**.
The `PgHybridRetriever`'s scalar stance filters act as a **Rhetorical
Firewall** — a gate that operates before the LLM's context window, not
after.

During retrieval, the RRF merge produces a ranked list of candidate clauses.
The scalar filters then evaluate each candidate against the interpersonal
payload. Clauses that fail the filter are excluded from the result set.
They never enter the synthesis prompt. The LLM never sees them.

This is semantic air gapping: the LLM's context window is isolated from
manipulative, emotionally charged, or low-formality text not by a prompt
instruction ("ignore manipulative content") but by a deterministic filter
that operates at the data layer, before the model's input is assembled.

It is also semantic data sanitization: the ideational payload (the facts)
passes through to the model, but the interpersonal payload (the persuasion)
is filtered, labeled, and structurally separated. The harmful component of
manipulative text — its rhetorical force — is sanitized out of the context
window while the informative component — its factual content — is preserved.

### What It Gives the System

A defense layer that does not depend on the LLM's cooperation. Prompt-level
defenses ("do not be manipulated") compete with adversarial content on the
same channel and can be overridden. The Rhetorical Firewall operates one
layer below: it removes the manipulative content from the channel before the
model has a chance to be influenced by it. The defense is structural, not
behavioral.

See [docs/use-cases/llm-role-isolation.md](use-cases/llm-role-isolation.md)
for why prompt-level defenses fail and why a structural layer is needed.

---

## The Synthesis

None of these domains individually solves the problem of LLM context
poisoning. SFL provides the metadata but not the security model. CBT
provides the distortion taxonomy but not the retrieval mechanism. Cognitive
neuroscience provides the consolidation pattern but not the linguistic
annotation. Existential philosophy provides the facticity/interpretation
distinction but not the storage schema. The Unix philosophy provides the
composability but not the security posture. Cybersecurity provides the
air-gapping model but not the semantic filter dimensions.

The SFL Engine is the point where these threads converge:

- SFL metadata becomes the filter dimensions (cybersecurity applies them).
- CBT distortions become the exclusion criteria (SFL metadata detects them).
- Neural consolidation becomes the context management pattern (Rolling
  Synthesis implements it).
- Existential facticity becomes the payload separation schema (the database
  enforces it).
- Unix pipes become the two-pass architecture (type contracts protect it).
- Air gapping becomes the Rhetorical Firewall (scalar filters implement it).

### The Goal: Modular Middleware

The ultimate goal is to take this interdisciplinary framework and offer it
as **modular middleware for standard RAG pipelines**.

The engine's two-pass annotation pipeline, payload separation schema, and
scalar stance filters are not coupled to a specific LLM, a specific vector
database, or a specific retrieval strategy. They are a pre-processing and
retrieval-filtering layer that can sit between any document store and any
LLM-based generation step:

```
Standard RAG:  Documents → Embed → Vector Store → Retrieve → LLM
                                   ↑
                              (topic only)

Safe RAG:      Documents → SFL Annotate → Embed + Stance Metadata → Store
                                                                    ↓
                          Retrieve (RRF + Stance Filters) ←── Query
                                    ↓
                          LLM (context window: filtered, objective)
```

The middleware position — between storage and generation — is where the
Rhetorical Firewall operates. It does not replace the LLM, the vector
database, or the retrieval algorithm. It augments them with a filter
dimension they do not have: the dimension of *how something was said*.

---

## Related

- [README — The Core Hypothesis: Stance-Filtered RAG (Safe RAG)](../README.md)
- [docs/use-cases/llm-role-isolation.md](use-cases/llm-role-isolation.md) — the Rhetorical Firewall hypothesis
- [ROADMAP.md](../ROADMAP.md) — Rolling Synthesis, Cognitive Gas, Semantic Convergence
- [lib/sfl/core/types/](../lib/sfl/core/types/) — IdeationalPayload, InterpersonalPayload
- [lib/sfl/store/pg_hybrid_retriever.rb](../lib/sfl/store/pg_hybrid_retriever.rb) — the stance filters
