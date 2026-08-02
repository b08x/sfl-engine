# SFL Query Router — Design

**Status**: validated design, not yet implemented.

## What this is

A standalone query-classification-and-dispatch service: takes a natural-language
query, classifies it against a deployment-defined taxonomy using SFL Engine's
existing Pass 1 pipeline plus a local zero-shot classifier, dispatches the
query to the matching LLM provider/model, and returns the answer plus routing
metadata. Built to be genuinely insertable into any agent/RAG pipeline via
plain REST — not tied to any one consumer's taxonomy (the coding/writing/
summarization/Q&A split from the interview-question prompt that originated
this, and a hypothetical 5-way IT-ticket differential explored as a stress
test, are both just *instances* of the same config-driven mechanism, not
requirements baked into the code).

## Why Pass 1 only, no Pass 2 LLM call before routing

SFL Engine's Pass 2 (LLM-based) annotation adds modality_weight (epistemic
certainty) and tenor (formality/social distance). Neither encodes *domain* —
a confident coding request and a confident writing request can have
near-identical modality/tenor. Concrete check: "Write a Python function that
sorts a list of dicts by key" and "Write a warm, engaging blog intro about
sustainable gardening" are both imperative+material at Pass 1, structurally
indistinguishable — but Pass 2 doesn't close that gap either, since neither
of its fields encodes subject matter. Adding Pass 2 to the routing path would
cost one extra LLM call per routing decision without solving the actual
ambiguity. The real fix is semantic classification over the Goal-participant
text Pass 1 already extracts for free (see Classifier below) — not a second
LLM call.

## Architecture

```
services/router/
├── Dockerfile              # Ruby + Python/spaCy, no Postgres
├── Gemfile                 # minimal: falcon, rack, ruby_llm, informers, dry-types/struct, zeitwerk
├── config.ru                # Rack entry point
├── exe/sfl-router            # boot script (mirrors exe/sfl-api)
├── lib/router/
│   ├── boot.rb               # composition root — ENV + taxonomy config -> collaborators
│   ├── taxonomy.rb           # loads/validates the YAML taxonomy config
│   ├── classifier.rb         # Pass 1 structural filter + ONNX zero-shot decision
│   ├── dispatcher.rb         # category -> LLM::ChatFactory call -> answer
│   └── api/server.rb         # Rack app: POST /route, GET /health
└── config/taxonomy.yml       # deployment-specific category definitions
```

**Reused as-is from `lib/sfl/core/`** (required via relative `$LOAD_PATH`,
not copied/duplicated): `PassOne::SpacySidecarParser`, `PassOne::
IdeationalExtractor`, `Types::*` (clause/participant structs). **Reused from
`lib/sfl/llm/`**: `ChatFactory`, `Config` — the same per-task provider/model
resolution pattern already used for `pass_two_annotation`/`embedding`, with
taxonomy-defined categories standing in for `Boot::TASK_NAMES`'s fixed four.

**Not reused**: `Store::*` (no Postgres — a routing decision is stateless),
`Analysis::Engine` (no conversation/document aggregation), the review-queue/
corpus-browser routes from `lib/sfl/api/`. This is what keeps the router a
genuinely lightweight, separately-deployable sibling service rather than a
new route bolted onto the full operator-console app.

Lives in the same repo as `sfl-engine` (not a new repo, not an extracted
gem) — reuses the well-tested Pass 1 machinery directly via `$LOAD_PATH`,
with its own Dockerfile/deploy, same multi-service-one-repo pattern already
established in `docs/dockerization-strategy.md` (api/migrate/webui).

## Transport

Plain REST/JSON only for v1. Universal across languages — the actual
requirement behind "insertable into any agent/RAG pipeline." An MCP server
front-end was considered (relevant for Claude-based consumers specifically)
but deferred: not worth building speculatively without a concrete Claude-
native consumer wanting it; can be added later as a thin adapter over the
same core if that need materializes.

## Taxonomy configuration

One YAML file per deployment, mounted at runtime (`ROUTER_TAXONOMY_PATH`,
default `config/taxonomy.yml`):

```yaml
categories:
  - name: coding
    match:
      process_type: [material]
      mood: [imperative]
    classify_label: "a request to write or debug code"
    llm:
      provider: anthropic
      model: claude-opus-5

  - name: writing
    match:
      process_type: [material, verbal]
      mood: [imperative]
    classify_label: "a request to write documentation, a notification, or other written communication"
    llm:
      provider: anthropic
      model: claude-sonnet-5

  - name: summarization
    match:
      process_type: [verbal, mental]
      mood: [interrogative, imperative]
    classify_label: "a request to summarize or condense existing content"
    llm:
      provider: openrouter
      model: mistralai/mistral-small-3.2-24b-instruct

  - name: general_qa
    match:
      process_type: [relational, mental]
      mood: [interrogative]
    classify_label: "a general factual or definitional question"
    llm:
      provider: openrouter
      model: mistralai/mistral-small-3.2-24b-instruct

default_category: general_qa   # required at boot — the "nothing matched" fallback
min_confidence: 0.55           # below this, falls back to default_category regardless of top score
```

`writing` and `summarization` deliberately overlap on `process_type: verbal`
(both are legitimately "verbal process" per SFL — see Classifier below for
why this is fine, not a bug) but are still cleanly disjoint categories
because Stage B's semantic classification, not `process_type` alone, makes
the final call between them.

**Env vars** (mirrors `.env`'s existing `SFL_TASK_*` pattern): `ROUTER_TAXONOMY_PATH`,
`ROUTER_API_KEY` (inbound auth), plus the same provider key vars already in
`Boot::REQUIRED_KEY_ENV_BY_PROVIDER` (`ANTHROPIC_API_KEY`, `OPENROUTER_API_KEY`,
etc.). `Taxonomy` validates at boot that every referenced `llm.provider` has
its required key present — fails loudly at startup, never discovered
mid-request (same philosophy as `SFL::Boot::Error`).

## Classifier — two-stage

**Stage A — Pass 1 structural filter** (deterministic, free): `SpacySidecarParser`
+ `IdeationalExtractor` produce `{process_type, mood, participants}` for the
query. Categories whose `match.process_type`/`match.mood` don't include the
query's values are eliminated. Cheap, and alone already fully separates
imperative-vs-interrogative and, among interrogatives, relational
(definitional Q&A) from verbal/mental (summarization) — see the SFL-driven
prompt-engineering research surfaced during design (Notebook collection,
`Research/SFL-Prompt-Engineering-Framework-Development.md`), which
independently maps Relational -> "classification/ontology" and Verbal ->
"summaries/press releases," corroborating this split.

**Stage B — local zero-shot semantic decision** (deterministic-ish, still
free, no LLM call): among the categories surviving Stage A,
`Informers.pipeline("zero-shot-classification")` (verified via Context7
against `ankane/informers`'s actual API —
`classifier.(text, candidate_labels, hypothesis_template:, multi_label:)` ->
`{sequence:, labels:, scores:}`, softmax-normalized) decides using the
Pass-1-extracted Goal-participant text as the premise and each surviving
category's `classify_label` as the candidate label set. This is what
actually separates `coding` from `writing` (both imperative+material) and
`writing` from `summarization` (both verbal) — the ambiguity Pass 1's
structural fields alone can't resolve, using the participant text Pass 1
already extracted for free rather than a hand-maintained keyword list or an
extra LLM call.

**Confidence is the classifier's real top-label score** (e.g. `0.87`), not a
fabricated number — runs fully local, no network call. If the top score is
below `min_confidence`, falls back to `default_category` with the real (low)
score still reported, so the caller can see *why* it fell back rather than
just that it did.

## Data flow

```
1. POST /route {query: "..."}  [Authorization: Bearer <ROUTER_API_KEY>]
       │
2. Api::Server validates auth (before any Pass 1 work — never pay for a
   parse on an unauthenticated request), validates body, calls Classifier.classify(query)
       │
3. Classifier:
   a. SpacySidecarParser.parse(query) -> tokens/deps
   b. IdeationalExtractor.extract(tokens) -> { process_type, mood, participants }
   c. Stage A: Taxonomy narrows to structurally-matching categories
   d. Stage B: Informers zero-shot classification decides among survivors
      (or applies default_category if none survived Stage A, or if top
      score < min_confidence)
       │
4. Dispatcher.call(category, query) -> LLM::ChatFactory.for(category.llm.provider, category.llm.model)
                                        .chat(query) -> answer text
       │
5. Server responds 200:
   {
     category: "coding",
     confidence: 0.87,
     dispatched: { provider: "anthropic", model: "claude-opus-5" },
     answer: "...",
     debug: {
       mood: "imperative", process_type: "material",
       scores: { coding: 0.87, writing: 0.09, ... }
     }
   }
```

No conversation/session state — each `/route` call is fully independent.
Deliberately stateless; a multi-turn/differential-narrowing shape (relevant
for something like iterative ticket triage) was considered during design and
explicitly scoped out as a different problem shape, not this service's job.

## Error handling

Following this codebase's existing D9 philosophy ("no un-rescued crash for
expected operational failures") and F11 pattern (partial-failure isolation,
already used in `pg_embedding_store.rb` and `cli.rb`'s batch loop):

| Failure | Handling |
|---|---|
| Sidecar fails to start / crashes mid-parse | Existing `SidecarError`, caught at the API layer -> `503 {error: "pass1_unavailable"}` |
| ONNX model fails to load at boot | `Router::Boot` fails loudly at startup — deploy-time problem, not per-request |
| No category matches structurally | Falls back to `default_category` (required, validated present at boot) |
| Top classifier score `< min_confidence` | Falls back to `default_category`, real score still reported in response |
| Configured LLM provider's API key missing | Caught at boot, same as `Boot::REQUIRED_KEY_ENV_BY_PROVIDER` |
| Downstream LLM call fails | `502 {error: "dispatch_failed", category:, provider:, model:}` — classification result still reported even though generation failed |
| Malformed/empty request body | `400 {error: "query is required"}` |
| Missing/invalid `ROUTER_API_KEY` | `401`, before any Pass 1 work happens |

**Deliberate non-goal: no retry logic on LLM dispatch.** A caller building
its own agent/RAG pipeline almost certainly already has a retry/fallback
policy; a second, invisible retry layer underneath would make failures
harder to reason about, not easier. Report plainly, let the caller decide.

## Testing

- **`Taxonomy`**: unit tests — YAML parsing, `default_category` presence,
  per-category provider key-presence validation at boot (mirrors
  `spec/boot/boot_spec.rb`'s existing `REQUIRED_KEY_ENV_BY_PROVIDER` coverage).
- **`Classifier`**: fake ONNX pipeline double (injectable `classify:`
  callable, same DI pattern `PgEmbeddingStore`/`Embedder` already use for
  `provider:`) for the fast unit suite — never loads the real model there.
  Separate, explicitly-tagged integration spec runs the real
  `Informers.pipeline` against a small fixed set of example queries per
  category, asserting top-label sanity (the one place a real model load is
  worth the cost — it's the only way to catch a `classify_label` that
  doesn't actually discriminate well in practice).
- **`Dispatcher`**: fake `LLM::ChatFactory`-compatible double, asserts
  correct provider/model requested per category — no real API calls in the suite.
- **`Api::Server`**: `rack-test` request specs (matching `spec/api/*`
  conventions) covering the full error-handling table above — auth-before-parse
  ordering, each failure mode's status/body shape, happy path end-to-end with fakes.
- No live spaCy sidecar or live LLM calls in the default `rake` task — same
  boundary this repo already draws elsewhere.

## Open items for implementation time

- Confirm final `min_confidence` default empirically once real example
  queries are run through Stage B, not guessed at design time.
- `services/router/Gemfile`'s exact dependency list (Falcon/Rack versions
  should track `sfl-engine`'s own, `informers` is new to this repo entirely).
- Whether `Router::Boot` needs its own `.env`-equivalent or reads the same
  `sfl-engine` `.env` file — leaning toward its own, since it's a genuinely
  separate deployable, but not settled.
