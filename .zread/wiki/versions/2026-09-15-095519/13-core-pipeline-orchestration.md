The `SFL::Core::Pipeline` class is the single composition point for the end-to-end compile use case: it binds Pass 1 (syntactic parsing + ideational extraction) and Pass 2 (LLM annotation) into one dry-monads Result chain, with optional clause persistence, embedding generation, and result caching. It is not the application's global composition root — that role still belongs to `Boot` in Phase 4 work — but for every caller that asks the engine to "compile a document," Pipeline is the stage where the two passes are wired and executed.

## The Five-Stage Compile Chain

`Pipeline#compile` is structured as a five-stage `dry-monads` bind ladder. Each stage returns `Success` or `Failure`, and `#bind` guarantees that a failure short-circuits the rest of the chain without any explicit guard at every step:

1. **Parse** — `pass_one.process(text, document_id:)` runs through `SFL::Core::PassOne::Engine`, which wraps the injected `SyntacticParser` port. A `PassOne::Error` maps to `Failure([:pass_one_failed, message])`.
2. **Pair with Ideational** — each syntactic clause is paired with `ideational_extractor.extract(clause)`, producing `[clause, ideational]` tuples. This is the seam where Pass 1's output and Pass 2's required input are joined.
3. **Annotate** — `pass_two.annotate_batch(pairs, context:)` runs against the pairs, with context carrying `semantic_coherence_score`. Three paths exist: `pass_one_only` stubs all annotations via `Ports::Null::Annotator`; `resume && document_id` routes through `annotate_with_cache`; otherwise a plain `annotate_all` call.
4. **Persist** — if `store: true` and `document_id` is present, `clause_store.replace_document(document_id, annotated)` performs a single delete-then-insert write under one document_id.
5. **Embed** — if `embed: true` and `document_id` is present, `embedder.embed_batch` is called only on **leaf clauses** (clauses no other clause's `parent_clause_id` points at), then `embedding_store.replace_document` persists the mapping.

The whole chain is expressed in 10 lines of `bind` composition, making the orchestration point explicit and testable. Every stage already owns its own logging, timing, and error translation; Pipeline only orchestrates.

Sources: [lib/sfl/core/pipeline.rb#L1-L264], [lib/sfl/core/pass_one/engine.rb#L1-L62]

## Pass 1: Syntactic Parsing Is a Sidecar, Not a Ruby Library

The most important architectural fact about the pipeline is that **Pass 1 no longer shares the Ruby process at all**. `Core::PassOne::SpacySidecarParser` spawns `spacy_sidecar.py` via `Open3.popen2` over stdin/stdout NDJSON pipes. The Ruby-side `SyntacticParser` port is a duck-typed interface; the concrete adapter speaks the sidecar protocol. This is the direct translation of track decision 2: the legacy codebase had a hand-rolled pipeline that manually swept dead PyCall wrappers before Pass 2 to avoid a GIL/GVL deadlock. That workaround is now obsolete — there is no PyCall object graph left in the Ruby process to trip over. The Python sidecar is a separate process, isolated by `pgroup: true` so a terminal Ctrl+C only hits the Ruby side.

`PassOne::Engine` owns only the guard clause, instrumentation span, and error translation. The parser is injected, which means tests swap in `Null::Parser` or `Fake` adapters without touching the engine. The parser's one crash-and-retry is deliberately local: a transport failure restarts the subprocess exactly once; a persistently broken sidecar still surfaces as an error rather than looping forever.

Sources: [lib/sfl/core/pass_one/spacy_sidecar_parser.rb#L1-L161], [lib/sfl/core/pass_one/engine.rb#L1-L62], [lib/sfl/core/pipeline.rb#L17-L22]

## Ideational Extraction Is Deterministic, LLM-Free Rule Mapping

`PassOne::IdeationalExtractor` maps syntactic dependency structures to SFL ideational metafunction categories: process type, participants (semantic roles), and circumstances (adjuncts). No LLM calls are involved. It operates on the spaCy dependency output from the sidecar and applies five verb-lemma constant lists (mental, relational, verbal, behavioral, existential) plus a dependency-to-role mapping (`PARTICIPANT_ROLES`). The result is an `IdeationalPayload` carrying `clause_id`, `process_type`, `participants`, `circumstances`, and `raw_transitivity`. The extraction is deliberately dumb and deterministic — it is a post-processing translation layer, not a comprehension model.

Sources: [lib/sfl/core/pass_one/ideational_extractor.rb#L1-L153]

## Pass 2: The Annotator Port Contracts a Batch Shape, Not a Per-Clause Loop

`Core::Ports::Annotator` defines two methods: `annotate(clause, ideational, context:)` for the single-clause case and `annotate_batch(pairs, context:)` for the batch case. The batch method exists as a distinct method because the `ruby_llm` engine's batch schema is a genuinely different call shape and cost profile — not an implementation detail to hide. The pipeline passes fully-formed pairs (syntactic clause + ideational payload) plus optional `semantic_coherence_score` into the annotator. The annotator is responsible for producing `AnnotationResult` (interpersonal + textual payloads). A `pass_one_only` run skips this port entirely by substituting `Ports::Null::Annotator`.

Sources: [lib/sfl/core/ports/annotator.rb#L1-L32], [lib/sfl/core/pipeline.rb#L117-L140]

## Caching with Self-Healing Trust Boundaries

`Pipeline#annotate_with_cache` implements a content-addressed cache keyed by `SHA256(document_id + sentence_index + clause.text)`. The cache port contract is deliberately asymmetric: `Cache#partition` must return hit values **in the same call that identifies them as hits** — a fix for a legacy bug where hits were read twice (once for the hit/miss partition, once again to rebuild the original clause order).

The cache implementation adds one defensive layer on top of the generic contract: **self-heal poisoned caches**. The pipeline treats any cache hit whose `clause.interpersonal.annotation_source` is not in `TRUSTED_ANNOTATION_SOURCES` (i.e. `llm` or `human`) as a miss, and re-annotates those clauses. This matters because the cache is content-addressed and could contain stale or untracked fallback/stub values from older pipeline versions. Trusted hits are served directly; untrusted hits are re-annotated and their fresh results are written back to the cache if the new `annotation_source` is trusted.

Resume also explicitly ignores the cache when `pass_one_only` is true — there is nothing to cache because the annotations are stubs by construction, and caching them would poison the trust boundary.

Sources: [lib/sfl/core/pipeline.rb#L147-L176], [lib/sfl/core/ports/cache.rb#L1-L29], [lib/sfl/core/ports/file_cache.rb#L1-L74], [lib/sfl/core/types/trusted_annotation_sources.rb#L1-L33]

## Storage and Embedding: Separate Ports, Coordinated Writes

`ClauseStore` and `EmbeddingStore` are separate ports with separate concrete implementations (`PgClauseStore` / `PgEmbeddingStore`). The pipeline coordinates them: `ClauseStore#replace_document` is the single write entry point for clauses, and `EmbeddingStore#replace_document` persists a hash of `clause_id → vector`. 

`Pipeline#embed_all` only embeds **leaf clauses** — clauses whose `id` does not appear in any other clause's `parent_clause_id`. This is a deliberate design for chunk-splitting: when a future parent/child chunk-splitting pass populates `parent_clause_id`, the embedding store keeps vectors at chunk granularity rather than duplicating vectors up the ancestor chain. Until that pass lands, every clause is a leaf, so the embedding step is a no-op today. A re-run with the same `document_id` is idempotent: `replace_document` is delete-then-insert under one document_id, so stale clauses cannot survive.

Sources: [lib/sfl/core/pipeline.rb#L203-L235], [lib/sfl/core/ports/clause_store.rb#L1-L34], [lib/sfl/core/ports/embedding_store.rb#L1-L23]

## Value Objects and Serialization Boundaries

`Core::Types` defines all pipeline-shaped value objects: `SyntacticClause`, `IdeationalPayload`, `InterpersonalPayload`, `AnnotationResult`, `AnnotatedClause`, `Readability`, and the `AnnotationSource` enum (`llm`, `fallback`, `stub`, `chunk_artifact`, `human`). `Wire` is a separate module that owns JSON serialization of these structs, converting `Time` to ISO8601 so values survive JSON round trips through job queues, HTTP responses, and file persistence. Only `compiled_at` and `interpersonal.reasoning_trace.generated_at` need explicit `Time` parsing; every other nested struct is handled by Dry::Struct's own Hash coercion.

The `untrusted` flag on `AnnotatedClause` is derived at compile time: it is `true` if either the interpersonal or textual annotation is marked `untrusted`, so downstream consumers (QA scoring, HITL review, retrieval filters) can distinguish compiler-substituted values from real LLM annotations.

Sources: [lib/sfl/core/types/annotated_clause.rb#L1-L20], [lib/sfl/core/types/ideational_payload.rb#L1-L16], [lib/sfl/core/types/interpersonal_payload.rb#L1-L22], [lib/sfl/core/types/annotation_source.rb#L1-L17], [lib/sfl/core/wire.rb#L1-L90]

## How the Pipeline Fits the Rest of the System

The pipeline is consumed by three use cases, and all of them agree on a single wiring factory: `CLI#build_pipeline`.

- **Analysis::Engine** (conversation, documentation, knowledge base) calls `Pipeline#compile` per unit/artifact in its compile loop, forwarding `store`, `resume`, and `pass_one_only` options. It owns the review-queue enqueueing after compile, and it treats a failed `Pipeline#compile` as an `Analysis::Error`.
- **CLI** builds the pipeline once per run through `build_pipeline`, which wires the real `SpacySidecarParser` (or a `Null` parser when `--pass1-only`), a real `LLM::EngineBuilder`-produced annotator, `PgClauseStore`/`PgEmbeddingStore`, and conditional `FileCache` (only when `--resume`).
- **GUI** (`ReviewQueueViewModel`, `SaveAndRecompileSection`) calls `Pipeline#compile` directly for the "Save & Recompile" edit flow, with `store: true`, `embed: true`, and `resume: false`, then passes the `Dry::Monads` Result through `finish_recompile!` to detect stale selections during a concurrent compile.

`Pipeline#initialize` requires both `pass_one:` and `pass_two:` collaborators, even though `pass_one_only` makes `pass_two` redundant at runtime. The class comment explicitly documents why: it keeps the required-kwarg surface uniform across all callers, so a real `LLM::Engine` built via `EngineBuilder` is never invoked when `--pass1-only` is set — the fake annotator satisfies the kwarg cheaply, and `Boot.call(require_llm: false)` is what actually skips the API-key validation and ChatFactory cost.

Sources: [lib/sfl/cli.rb#L463-L507], [lib/sfl/analysis/engine.rb#L1-L98], [lib/sfl/gui/review_queue_view_model.rb#L1-L50], [lib/sfl/core/pipeline.rb#L31-L60]

## Runtime Modes at a Glance

| Mode | `pass_one_only` | Cache | Annotator called? | Stores clauses? | Embeds? |
|---|---|---|---|---|---|
| Full compile | false | false | Yes (`annotate_all`) | `store: true` + `document_id` | `embed: true` + `document_id` |
| Resume compile | false | true | Yes, unless cache hits | `store: true` + `document_id` | `embed: true` + `document_id` |
| Pass-1-only stub | true | Ignored | No (`stub_annotate_all`) | `store: true` + `document_id` | `embed: true` + `document_id` |

Sources: [lib/sfl/core/pipeline.rb#L84-L98], [lib/sfl/cli.rb#L482-L507], [spec/core/pipeline_spec.rb#L43-L197]

## Visual Overview: Pipeline as the Orchestration Hub

```mermaid
flowchart TD
    Input[Raw Text] --> Pass1[Pass 1: SpacySidecarParser<br>syntactic clauses + raw dependency tree]
    Pass1 --> Pair[Pair with IdeationalExtractor<br>I deationalPayload per clause]
    Pair --> Annotate{Annotate dispatch}
    Annotate -->|pass_one_only| Stub[Null::Annotator stubs<br>interpersonal/textual payloads]
    Annotate -->|resume + document_id| Cache[FileCache/partition<br>hits served, misses re-annotated]
    Annotate -->|plain| LLM[LLM::Engine / Annotator port<br>interpersonal + textual]
    Stub --> Output[AnnotatedClause[]]
    Cache --> Output
    LLM --> Output
    Output --> Persist[ClauseStore replace_document<br>delete-then-insert per document]
    Output --> Embed[Embedder embed_batch on leaf clauses<br>EmbeddingStore replace_document]
    Persist --> Done[Success(AnnotatedClause[])]
    Embed --> Done
    Input -->|PassOne::Error| Fail[Failure(:pass_one_failed)]
    Fail --> Done
```

The diagram separates the two orchestrator branches (stub vs. cache vs. LLM) that `Pipeline#annotate` can take, then converges on the common output → persist + embed stage.

## Practical Consequences for Developers

- **Passing `pass_one_only: true` is the sanctioned way to get placeholder annotations** without building a fake annotator elsewhere. It is the single structural fix for the golden-master bug where two independent code paths disagreed on whether Pass 2 should run.
- **Cache keys are content-addressed, not document-addressed.** Two clauses with identical text at different `sentence_index` values get different keys — `sentence_index` disambiguates repeated boilerplate headers.
- **Never call `Embedder#embed_batch` without a `document_id`.** The pipeline deliberately skips embedding when there is no document_id, because an embed run with no document_id has nothing to replace idempotently on a re-run.
- **Cache is only read when `resume: true` and `document_id` is present.** The code explicitly guards for both in the same condition, so a resume in a throwaway document cannot accidentally serve stale annotations.
- **The pipeline owns `compiled_at` generation.** All timestamping is centralized in `build_annotated_clause`, so a re-run gets a fresh `compiled_at` per clause, which matters for review-queue change detection.
- **Time serialization is the contract for JSON round-trips.** `Core::Wire` exists exactly because `Dry::Struct` `to_h` leaves `Time` objects that do not survive JSON; cache files, API responses, and job payloads all go through `Wire.dump`/`Wire.load_annotated_clause`.

Sources: [lib/sfl/core/pipeline.rb#L1-L264], [lib/sfl/core/ports/file_cache.rb#L1-L74], [lib/sfl/core/pipeline.rb#L147-L176], [lib/sfl/core/types/wire.rb]

## Next Section

For the layers that sit directly below the pipeline — the deterministic thought-mapping of Pass 1 and the LLM-powered metafunction annotation of Pass 2 — read [Pass 1: Syntactic Parsing](pass-1-syntactic-parsing) and [Pass 2: LLM Annotation](pass-2-llm-annotation).

For analysis use cases that drive the pipeline (conversation analysis, documentation ingestion, knowledge base assessment), refer to [Analysis Engine](analysis-engine). For the persistence and retrieval stack that the pipeline's optional storage and embedding stages feed, read [Postgres Integration](postgres-integration) and [Hybrid Retrieval with RRF](hybrid-retrieval-with-rrf).