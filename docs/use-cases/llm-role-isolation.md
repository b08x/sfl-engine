# LLM Role Isolation: The Rhetorical Firewall Hypothesis

**Status:** Core Hypothesis — SIFT-reviewed implementation  
**Parent:** [Architectural Lineage](../architectural-lineage.md)  
**Assessment:** [SIFT System Design Assessment](../sift-system-design-assessment.md)

---

## Current engineering assessment

The implementation has a coherent ports-and-adapters architecture and a reusable two-pass pipeline. A SIFT system design review scored it **78/100**: good and suitable for continued development or controlled internal use, but not yet an unconditional production-ready system.

The review identified these hardening priorities:

1. Make clause re-annotation and review-audit recording one transactional operation.
2. Sanitize unexpected API errors and keep internal exception details server-side.
3. Resolve the Bundler `~> 2.6` mismatch before treating automated verification as complete.
4. Add architecture-level tests for dependency direction and composition boundaries.

These are engineering readiness findings, not evidence against the Rhetorical Firewall hypothesis. The hypothesis still requires corpus-based outcome studies, filter-effectiveness experiments, and adversarial robustness testing.

See the [full SIFT system design assessment](../sift-system-design-assessment.md).

---

## Architectural framing: separation of concerns

The same design can be understood as an MVC-like separation applied to language metadata:

- **Ideational payload — Model-like:** processes, participants, and circumstances represent the event or claim being described.
- **Interpersonal payload — View-like:** mood, modality, tenor, and attitude describe how that claim is presented to a reader.

This is an analogy, not a claim that interpersonal metadata is mere presentation. In this system it is a security-relevant retrieval signal. The database boundary makes it possible to constrain rhetorical influence while retaining the underlying clause for evidence and citation.

The security analogy is input sanitization: influence-bearing metadata is classified and filtered before it enters the synthesis context. The implementation does not prove a clause is malicious, guarantee that persuasion has been removed, or establish that the model will always reason more accurately. Those are empirical questions for the adversarial and outcome studies listed below.

---

## The Problem: Context Poisoning

Standard RAG pipelines retrieve text by semantic similarity and inject it
into the LLM's context window as fused prose. The model has no structural
way to distinguish *what was said* from *how it was said*. A clause like
"Everyone agrees this migration is catastrophic!" arrives as a single
indivisible string — factual claim and persuasive frame baked together.

The LLM absorbs the stance along with the facts. This is **context
poisoning**: the model's reasoning is influenced not by the content of the
retrieved text, but by its rhetorical posture.

### Why Prompt-Level Defenses Fail

The standard mitigation is a prompt instruction: "do not be influenced by
the tone of retrieved text; evaluate only the factual content." This fails
for a structural reason: the defense and the attack operate on the same
channel.

The prompt instruction is text. The adversarial content is text. They
compete for the same attention mechanism. A sufficiently persuasive clause
—"Everyone agrees..." — carries social-proof modality that overrides the
prompt's instruction to ignore social proof. The defense is behavioral
("try not to be influenced"); the attack is structural (the clause's
interpersonal profile is engineered to override behavioral defenses).

This is the **single-channel illusion**: the belief that a text instruction
can reliably filter text content, when both are processed by the same
neural architecture.

---

## The Hypothesis: Structural Defense via Payload Separation

The Rhetorical Firewall hypothesis states:

> A defense against context poisoning must operate at the data layer, not
> the prompt layer. By separating the ideational payload (facticity) from
> the interpersonal payload (stance) at storage time — and filtering the
> interpersonal payload before the LLM's context window is assembled — the
> system structurally prevents the model from conflating "what was said"
> with "how it was said."

### The Three Requirements

1. **Separation at storage time**: Ideational and interpersonal metadata
   must be stored in separate tables, independently indexable. They must
   never be fused into a single string before the LLM sees them.

2. **Filtering at retrieval time**: Scalar filters on interpersonal fields
   (modality, tenor, mood) must operate on the candidate set *before* the
   context window is assembled. Clauses that fail the filter are excluded
   from the result set. The LLM never sees them.

3. **Presentation as labeled fields**: The synthesis prompt must present
   ideational and interpersonal data as labeled, separable inputs — not as
   a single prose paragraph. The model must work to reconstruct fused
   meaning from distinct fields.

---

## The Attack Vector: Parahuman Manipulation

Parahuman manipulation is text engineered to exploit the LLM's tendency to
absorb rhetorical stance from context. It does not require technical
sophistication — natural language is inherently persuasive, and LLMs
trained on human text have learned to follow social cues embedded in
prose.

### Common Patterns (CBT-Derived Taxonomy)

| Pattern | Linguistic Fingerprint | SFL Signature |
|---------|----------------------|---------------|
| **Social proof** | "Everyone knows...", "Experts agree..." | Low tenor, high modality, declarative mood |
| **Emotional reasoning** | "This is clearly terrible..." | Low tenor, exclamative mood, high modality |
| **Hyperbolic extremes** | "This always fails..." | Low tenor, universal modality, material process |
| **Mind reading** | "You know this is wrong..." | Low tenor, high modality, mental process |
| **Should statements** | "You must comply..." | Low tenor, imperative mood, high modality |

These patterns are not detected by content analysis. They are detected by
their **structural fingerprints** — the interpersonal metadata that the SFL
Engine extracts and indexes.

### Why Standard RAG Is Vulnerable

In standard RAG, these patterns enter the context window as fused prose.
The LLM sees "Everyone agrees this is catastrophic!" and processes it as a
single token sequence. The social-proof modality, the hyperbolic framing,
and the declarative pressure are all present in the same input. The model
has no structural mechanism to separate the factual claim ("this is
catastrophic") from the persuasive frame ("everyone agrees").

---

## The Defense: Rhetorical Firewall

### How It Works

1. **Annotate**: The two-pass pipeline extracts SFL metadata for every
   clause. Pass 1 produces the ideational payload (process type,
   participants, circumstances). Pass 2 produces the interpersonal payload
   (mood, modality, tenor, attitude).

2. **Store separately**: Ideational and interpersonal payloads are stored in
   separate PostgreSQL tables with separate indices. They are never fused.

3. **Retrieve with filters**: The `PgHybridRetriever` merges vector
   similarity and keyword search via RRF, then applies scalar stance
   filters:

   ```ruby
   # Pseudocode for the Rhetorical Firewall
   candidates = hybrid_retrieve(query, limit: 100)
   filtered = candidates.select do |clause|
     clause.interpersonal.modality >= params[:min_modality] &&
     clause.interpersonal.tenor >= params[:min_tenor] &&
     params[:moods].include?(clause.interpersonal.mood)
   end
   ```

4. **Synthesize from labeled fields**: The `ContextSynthesizer` presents
   ideational and interpersonal data as labeled fields in the synthesis
   prompt:

   ```
   Clause [doc-123, turn-5]:
     Ideational: material process; Actor: migration; Goal: failure;
                 Circumstance: current state
     Interpersonal: mood=declarative; modality=0.85; tenor=0.3;
                    attitude=social_proof
     Text: "Everyone agrees the migration is failing!"
   ```

   The LLM receives the factual content and the stance metadata as
   distinct inputs. It must work to reconstruct the fused meaning — and
   the evidence suggests this extra step is enough to prevent automatic
   stance absorption.

### What the Filters Exclude

| Filter | Excludes | CBT Pattern |
|--------|----------|-------------|
| `min_modality > 0.7` | Hedged, uncertain, speculative text | Catastrophizing, emotional reasoning |
| `min_tenor > 0.6` | Informal, emotionally charged register | Hyperbolic extremes, personalization |
| `mood != exclamative` | Pressure tactics, urgency framing | Should statements, labeling |
| `mood != imperative` | Commands, directives | Should statements, demands |

### What the Filters Preserve

The filters operate on the **interpersonal payload only**. The **ideational
payload** — the factual content — passes through to the LLM unchanged. A
clause like "Everyone agrees the migration is failing!" is excluded not
because its factual claim is wrong, but because its interpersonal profile
matches a cognitive distortion's structural fingerprint. The factual claim
("the migration is failing") may be true; the persuasive frame ("everyone
agrees") is what gets filtered.

---

## The Single-Channel Illusion

### Why Behavioral Defenses Fail

A behavioral defense is an instruction to the LLM: "ignore the tone of
retrieved text." This fails because:

1. **The defense is text.** It competes with adversarial content for the
   same attention mechanism.
2. **The defense is generic.** "Don't be manipulated" doesn't know what
   manipulation looks like. It can't detect social-proof modality or
   hyperbolic framing.
3. **The defense is late.** By the time the LLM reads the instruction, it
   has already processed the adversarial content. Attention has already been
   allocated.

### Why Structural Defenses Work

A structural defense operates at the data layer, before the LLM's context
window is assembled:

1. **The defense is deterministic.** Scalar filters don't "try" not to be
   influenced. They exclude clauses that fail the filter. Period.
2. **The defense is specific.** It knows what manipulation looks like
   (CBT-derived fingerprints) and filters for those patterns.
3. **The defense is early.** It operates before the model sees the content.
   The adversarial clause never enters the context window.

This is the difference between a behavioral instruction ("don't be
manipulated") and a structural constraint ("this clause will not reach the
model"). The first is a suggestion. The second is a guarantee.

---

## Evidence and Status

### What Has Been Demonstrated

- The two-pass pipeline extracts SFL metadata reliably (Phases 0-5
  complete).
- Scalar stance filters operate correctly on interpersonal payloads.
- The `ContextSynthesizer` presents labeled fields to the LLM.
- The `PgHybridRetriever` merges vector and keyword search with filter
  support.

### What Has Not Been Demonstrated

- **Outcome studies**: No external corpus has been run through the system
  for any purpose. No findings exist. This document describes working
  infrastructure, not a study.
- **Filter effectiveness**: The hypothesis that stance filters change LLM
  reasoning outcomes has not been empirically validated.
- **Adversarial robustness**: The system has not been tested against
  adversarial inputs designed to bypass the filters.

### Next Steps

1. **Phase 6 (Hardening)**: Performance validation, coverage gate, YARD
   documentation.
2. **Filter tuning**: Measure how different filter thresholds affect LLM
   reasoning quality on held-out test sets.
3. **Adversarial testing**: Design inputs that attempt to bypass the
   Rhetorical Firewall and measure filter resilience.

---

## Related

- [Architectural Lineage](../architectural-lineage.md) — the intellectual foundations
- [README — The Core Hypothesis](../../README.md) — project overview
- [lib/sfl/store/pg_hybrid_retriever.rb](../../lib/sfl/store/pg_hybrid_retriever.rb) — the stance filters
- [lib/sfl/analysis/context_synthesizer.rb](../../lib/sfl/analysis/context_synthesizer.rb) — labeled field presentation
