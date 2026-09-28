The `AnnotatedClause` is the central aggregate of the SFL engine — the full, compiled output of the two-pass pipeline that turns raw text into linguistically annotated clauses. It is the structural anchor for storage, retrieval, review, synthesis, and graph visualization. Every clause that survives the compiler carries this shape, and every downstream pipeline component (storage, analysis, HTTP API, GraphQL, CLI golden masters) reads or writes it.

This page documents the `AnnotatedClause` type: its fields, its constituent payload structs, how it is assembled, how it round-trips through Persist, and how it is consumed across the codebase.

## Composite Structure and Field Semantics

`AnnotatedClause < Dry::Struct` is a value object defined in `lib/sfl/core/types/annotated_clause.rb`. It has **9 attributes** that fall into three groups: the syntactic core, the two metafunction payloads, and the provenance/timing envelope.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | `String` | Yes | Fresh UUID assigned at compile time — the **join key** persisted to storage and used for retrieval/review/graph lookups. |
| `text` | `String` | Yes | The raw clause surface string. |
| `syntactic` | `SyntacticClause` | Yes | Full pass-1 parse: tokens, groups, `root_index`, `sentence_index`, `parent_clause_id`, `readability`. |
| `ideational` | `IdeationalPayload` | Yes | Pass-1 transitivity output: `process_type` (material/mental/relational/verbal/behavioral/existential), semantic `participants`, `circumstances` (adjuncts), `raw_transitivity` hash. |
| `interpersonal` | `InterpersonalPayload` | Yes | Pass-2 annotation: `mood`, `modality_weight`, `tenor`, `speaker_attitude`, `reasoning`, `annotation_source`, `reasoning_trace`, `raw_classification`, `classification_status`, `untrusted`. |
| `textual` | `TextualPayload` | Optional | Pass-2 textual metafunction: `topical_theme`, `textual_theme`, `interpersonal_theme`, `rheme`, `theme_type`, `classification_status`. |
| `document_id` | `String` | Optional | Associates the clause with a compiled document for scoped storage, retrieval, and embedding. |
| `compiled_at` | `Time` | Yes | Wall-clock timestamp of the compile. Serialized to ISO8601 via `Wire.dump`. |
| `untrusted` | `Bool` | Default `false` | Flag set when either `interpersonal.untrusted` or `textual&.untrusted` is true (e.g. when Pass 2 falls back to placeholder values). Used by `finish_report` to compute the degraded-run exit code. |

**Sources:** [lib/sfl/core/types/annotated_clause.rb#L1-L21](lib/sfl/core/types/annotated_clause.rb#L1-L21), [lib/sfl/core/types/syntactic_clause.rb#L1-L24](lib/sfl/core/types/syntactic_clause.rb#L1-L24), [lib/sfl/core/pipeline.rb#L195-L209](lib/sfl/core/pipeline.rb#L195-L209)

## The Three Payload Pillars: Metafunctional Decomposition

The `AnnotatedClause` is the structural realization of SFL's **metafunctional three-dimensional model**. Each dimension maps to a dedicated payload struct:

### Ideational Payload (Pass 1)

`IdeationalPayload` captures *what is going on* in the clause — the transitivity system. Produced by `PassOne::IdeationalExtractor` (`lib/sfl/core/pass_one/ideational_extractor.rb`), it is rule-based (no LLM).

| Attribute | Type | Description |
|-----------|------|-------------|
| `clause_id` | `String` | Passage key — matches the outer `AnnotatedClause#id` on the round trip (though storage collapses it). |
| `process_type` | `ProcessType` | Transitivity process: `material`, `mental`, `relational`, `verbal`, `behavioral`, `existential`. Classifies the root verb. |
| `participants` | `Array<Participant>` | Semantic roles extracted from dependency labels (`nsubj`, `dobj`, `iobj`, `attr`, `oprd`). |
| `circumstances` | `Array<String>` | Adjuncts in `"dep:text"` format (`nsubj:Alice`, `prep:in`, `advmod:quicker`). |
| `raw_transitivity` | `Hash` | Full transparency parse: `{ root: {...}, dependencies: [...] }`. |

Sources: [lib/sfl/core/types/ideational_payload.rb#L1-L17](lib/sfl/core/types/ideational_payload.rb#L1-L17), [lib/sfl/core/pass_one/ideational_extractor.rb#L1-L154](lib/sfl/core/pass_one/ideational_extractor.rb#L1-L154)

### Interpersonal Payload (Pass 2)

`InterpersonalPayload` captures *how the speaker engages* with the clause — mood, modality, tenor, and the reasoning that produced the annotation. This is the LLM-passed output.

| Attribute | Type | Description |
|-----------|------|-------------|
| `clause_id` | `String` | Matches the outer `AnnotatedClause#id`. |
| `mood` | `MoodType` | Declarative, interrogative, imperative, exclamative, indicative, fragment (canonical values from `ClassificationRegistry`). |
| `modality_weight` | `ModalityWeight` | Float 0.0–1.0, coercible (LLM-safe against integer boundaries). |
| `tenor` | `TenorValue` | Float 0.0–1.0, coercible (LLM-safe against integer boundaries). |
| `speaker_attitude` | `String` | Free-form LLM assessment of the speaker's attitude. |
| `reasoning` | `String` | LLM's free-form justification for the annotation. |
| `annotation_source` | `AnnotationSource` | Provenance: `llm`, `fallback`, `stub`, `chunk_artifact`, `human`. |
| `reasoning_trace` | `ReasoningTrace` | Structured derivation trace (premises → inference rule → conclusion → confidence → derivation_hash). |
| `raw_classification` | `String` | Un-normalized raw LLM output before the `ClassificationRegistry` normalizes it. |
| `classification_status` | `ClassificationStatus` | `exact`, `aliased`, `fuzzy`, or `unknown` from normalization. |
| `untrusted` | `Bool` | Set to `true` when the annotation is not from a trusted source. |

Sources: [lib/sfl/core/types/interpersonal_payload.rb#L1-L23](lib/sfl/core/types/interpersonal_payload.rb#L1-L23), [lib/sfl/core/types/mood_type.rb#L1-L13](lib/sfl/core/types/mood_type.rb#L1-L13), [lib/sfl/core/types/modality_weight.rb#L1-L15](lib/sfl/core/types/modality_weight.rb#L1-L15), [lib/sfl/core/types/tenor_value.rb#L1-L12](lib/sfl/core/types/tenor_value.rb#L1-L12)

### Textual Payload (Pass 2, Optional)

`TextualPayload` captures *how the clause hangs together* as a message — theme, rheme, and thematic progression. It is optional on `AnnotatedClause` because it is only produced when Pass 2 runs in full (not `--pass1-only`).

| Attribute | Type | Description |
|-----------|------|-------------|
| `clause_id` | `String` | Matches the outer `AnnotatedClause#id`. |
| `topical_theme` | `String` | The topical theme (what the clause is about in a thematic sense). |
| `textual_theme` | `String` | Textual thematic role. |
| `interpersonal_theme` | `String` | Interpersonal thematic role. |
| `rheme` | `String` | The rheme (what is said about the theme). |
| `theme_type` | `String` (enum) | Canonical theme type from `ClassificationRegistry`. |
| `untrusted` | `Bool` | Flag for compiler-substituted defaults. |

Sources: [lib/sfl/core/types/textual_payload.rb#L1-L22](lib/sfl/core/types/textual_payload.rb#L1-L22)

## How the Two-Pass Compiler Assembles an AnnotatedClause

The `Pipeline` class (`lib/sfl/core/pipeline.rb`) is the composition point. The lifecycle is a monadic bind chain:

1. **`parse(text, document_id)`** → `PassOne::Engine#process` returns `Array<SyntacticClause>`.
2. **`pair_with_ideational(clauses)`** → maps each clause to `[SyntacticClause, IdeationalPayload]` via `IdeationalExtractor`.
3. **`annotate(pairs, ...)`** → `PassTwo::Engine#annotate_batch` returns `Array<AnnotationResult>` (which contains `interpersonal` and `textual`).
4. **`build_annotated_clause(clause, ideational, annotation_result)`** → assembles the full `AnnotatedClause` (see the code at `lib/sfl/core/pipeline.rb#L195-L209`). Notable details:
   - `id` is `SecureRandom.uuid` — a **fresh UUID per compile**, distinct from the inner `SyntacticClause#id`.
   - `syntactic` gets a `readability` attribute attached (computed by `ReadabilityScorer`).
   - `untrusted` is `true` when `interpersonal.untrusted || textual&.untrusted == true`.
5. **`persist(annotated, ...)`** → `clause_store.replace_document(document_id, annotated)` persists the clause (only the outer `id` is stored).
6. **`embed_all(annotated, ...)`** → `embedding_store.replace_document` embeds only leaf clauses (those no other clause's `parent_clause_id` points at).

Sources: [lib/sfl/core/pipeline.rb#L1-L265](lib/sfl/core/pipeline.rb#L1-L265)

## Storage Round-Trip: What Survives and What Is Collapsed

`PgClauseStore#replace_document` (`lib/sfl/store/pg_clause_store.rb`) persists an `AnnotatedClause` array as **four SQL tables**, but only the outer `id` survives as a foreign key:

| SQL Table | Columns Derived From | Notes |
|-----------|---------------------|-------|
| `clauses` | `external_id` (= AnnotatedClause#id), `text`, `document_id`, `sentence_index`, `root_index`, `tokens` (jsonb), `groups` (jsonb), `parent_clause_id`, `embedding_status`, `readability_*`, `word_count` | The `external_id` is **not** a Postgres UUID; it's the string `AnnotatedClause#id`. `parent_clause_id` is a self-referencing FK with cycle-prevention trigger (db/migrations/011). |
| `ideational_payloads` | `clause_id` (= outer id), `process_type`, `participants` (jsonb), `circumstances` (jsonb), `raw_transitivity` (jsonb) | Real FK to `clauses.external_id` with `ON DELETE CASCADE`. |
| `interpersonal_payloads` | `clause_id` (= outer id), `mood`, `modality_weight`, `tenor`, `speaker_attitude`, `reasoning`, `annotation_source`, `reasoning_trace` (jsonb), `raw_classification`, `classification_status`, `untrusted` | Real FK with `ON DELETE CASCADE`; composite index on `(mood, modality_weight, tenor)` for scalar-filter queries. |
| `embeddings` | `clause_id` (= outer id), `embedding` (vector(768)), `model` | HNSW index, cosine distance. |

**The collapse:** `SyntacticClause#id`, `IdeationalPayload#clause_id`, and `InterpersonalPayload#clause_id` are all distinct UUIDs upstream (assigned per the type system), but `PgClauseStore` only records `AnnotatedClause#id` as the join key (`external_id`/`clause_id`). Every reconstructed clause collapses all three inner ids to the outer id. This is documented as an "accepted lossy round trip" in `PgClauseStore#replace_document`'s class comment.

**Reconstruction** (`reconstruct` in `PgClauseStore`) rebuilds the three payloads from the joined query, re-casting jsonb values to the dry-struct types the application expects.

**Sources:** [lib/sfl/store/pg_clause_store.rb#L1-L357](lib/sfl/store/pg_clause_store.rb#L1-L357), [db/migrations/001_create_clauses.rb#L1-L36](db/migrations/001_create_clauses.rb#L1-L36), [db/migrations/002_create_ideational_payloads.rb#L1-L26](db/migrations/002_create_ideational_payloads.rb#L1-L26), [db/migrations/003_create_interpersonal_payloads.rb#L1-L35](db/migrations/003_create_interpersonal_payloads.rb#L1-L35), [db/migrations/011_add_parent_clause_id_to_clauses.rb#L1-L83](db/migrations/011_add_parent_clause_id_to_clauses.rb#L1-L83)

## Serialization Boundary: Wire.dump / Wire.load

`AnnotatedClause` (and its nested structs) crosses process boundaries (HTTP, file persistence, golden-master JSON) through `SFL::Core::Wire`:

- **`Wire.dump(struct)`** recursively stringifies every `Time` attribute to ISO8601. Dry::Struct's `to_h` already coerces hashes/arrays, but `Time` objects would break JSON round-trips.
- **`Wire.load_annotated_clause(hash)`** reverses the Time transformation: it parses `compiled_at` and each `reasoning_trace.generated_at`, then passes the merged hash to `Types::AnnotatedClause.new` (Dry::Struct's Hash coercion handles the rest).

The same pattern applies to `ConversationTurn` and `AnalysisResult` for their respective round trips.

Sources: [lib/sfl/core/wire.rb#L1-L91](lib/sfl/core/wire.rb#L1-L91)

## How AnnotatedClause Flows Through the System

### 1. Retrieval (Scalar Stance Filters)

`Store::ClauseFilters` (`lib/sfl/store/clause_filters.rb`) applies filters against a joined query over `clauses` + `ideational_payloads` + `interpersonal_payloads`:

| Filter Key | SQL Target | Notes |
|------------|-----------|-------|
| `mood` | `interpersonal_payloads.mood` | Exact enum match. |
| `min_modality` / `max_modality` | `interpersonal_payloads.modality_weight` | Range boundaries. |
| `min_tenor` / `max_tenor` | `interpersonal_payloads.tenor` | Range boundaries. |
| `process_type` | `ideational_payloads.process_type` | Exact enum match. |
| `source_type` | `clauses.source_type` | Free-form provenance tag (`chat_native`, `vault_markdown`, etc.). |

The `RetrievalFilters` type (`lib/sfl/core/types/retrieval_filters.rb`) is a strict Dry::Struct, so unknown keys raise at construction — protecting against silently ignored filters.

Sources: [lib/sfl/store/clause_filters.rb#L1-L44](lib/sfl/store/clause_filters.rb#L1-L44), [lib/sfl/core/types/retrieval_filters.rb#L1-L45](lib/sfl/core/types/retrieval_filters.rb#L1-L45)

### 2. HTTP API

- **`GET /clauses`** (`app/routes/clauses.rb`): Calls `clause_store.find_all` with optional `document_id`, `annotation_source`, and scalar filters, paginated. The response maps each `AnnotatedClause` through `SFL::Core::Wire.dump`.
- **`POST /pipeline/compile`** (`app/routes/pipeline.rb`): Invokes `Pipeline#compile(text, document_id:, store:, embed:, resume:, pass_one_only:, semantic_coherence_score:)` and returns the resulting `AnnotatedClause` array.
- **`POST /clauses/:id/review`** (`app/routes/clauses.rb`): `ClauseReviewService#review` fetches the clause via `clause_store.find`, then either re-annotates it (via Pass 2) or records an audit decision in `annotation_reviews`.

Sources: [app/routes/clauses.rb#L1-L56](app/routes/clauses.rb#L1-L56), [lib/sfl/api/clause_review_service.rb#L1-L64](lib/sfl/api/clause_review_service.rb#L1-L64)

### 3. GraphQL / Graph Repository

`PgGraphRepository` (`lib/sfl/store/pg_graph_repository.rb`) builds `GraphNode` and `GraphEdge` structs from the same three-table join. `GraphNode` inlines `mood`, `tenor`, `process_type`, and `readability` from the joined rows — deliberately not a full nested `AnnotatedClause` (per the `RetrievalResult` design, a ranked row doesn't need the full payload).

Sources: [lib/sfl/store/pg_graph_repository.rb#L1-L107](lib/sfl/store/pg_graph_repository.rb#L1-L107)

### 4. Analysis Engine

`Analysis::Engine` (`lib/sfl/analysis/engine.rb`) receives `Array<AnnotatedClause>` as `turn.clauses`. It derives `ConversationTurn` (which inlines `AnnotatedClause` arrays), then computes `tenor_shift`, `cohesion`, `speaker_profiles`, `correlations`, `key_moments`, `example_passages`, and topic evolution. The `AnnotatedClause#interpersonal` payload is the primary data source for these derivations.

Sources: [lib/sfl/analysis/engine.rb#L1-L529](lib/sfl/analysis/engine.rb#L1-L529)

### 5. CLI Golden Masters

`sfl-analyze conversation|documentation` serializes `AnalysisResult` (with `ConversationTurn.clauses` containing `AnnotatedClause` objects) to `conversation_analysis.json` / `.csv` / `.md` files in `spec/fixtures/golden_master/` and compares them against new runs. The golden-master JSON shows the two shapes:
- **Conversations** (pass1-only runs): clauses carry `id`, `annotation_source: "stub"`, `reasoning_trace: null`.
- **Documentation** (full LLM runs): clauses carry `id`, `annotation_source: "llm"`, nested `reasoning_trace` with premises/inference_rule/conclusion/confidence/derivation_hash/generated_at.

Sources: [spec/fixtures/golden_master/conversation/conversation_analysis.json#L1-L120](spec/fixtures/golden_master/conversation/conversation_analysis.json#L1-L120), [spec/fixtures/golden_master/documentation/conversation_analysis.json#L1-L120](spec/fixtures/golden_master/documentation/conversation_analysis.json#L1-L120)

## Type Safety Guarantees and Constraints

1. **Enum integrity:** `MoodType`, `ProcessType`, and `AnnotationSource` are `String.enum` instances driven by `ClassificationRegistry.canonical_values`. This means the set of valid values is defined in exactly one place (the registry) and enforced at type construction time — a typo fails loudly, not silently.
2. **LLM-safe floats:** `ModalityWeight` and `TenorValue` are `Coercible::Float` (not `Strict::Float`). This was a deliberate live-verified fix for LLM providers emitting `0`/`1` integers instead of `0.0`/`1.0`. A strict constraint would have been a silent full-clause failure.
3. **Strict retrieval schema:** `RetrievalFilters` uses `schema.strict`, so an unknown key like `:mod` raises `Dry::Struct::Error::UnknownKeywordError` at construction time instead of the legacy `Hash#[]` behavior of silently no-oping.
4. **Database-level constraints:** The `clauses` table has a CHECK constraint (`parent_clause_id IS NULL OR parent_clause_id <> external_id`) and a BEFORE INSERT/UPDATE trigger that walks the ancestor chain and raises if a cycle is introduced. These are the only places the domain invariants are enforced at the database level.

Sources: [lib/sfl/core/types/mood_type.rb#L1-L13](lib/sfl/core/types/mood_type.rb#L1-L13), [lib/sfl/core/types/process_type.rb#L1-L11](lib/sfl/core/types/process_type.rb#L1-L11), [lib/sfl/core/types/modality_weight.rb#L1-L15](lib/sfl/core/types/modality_weight.rb#L1-L15), [lib/sfl/core/types/retrieval_filters.rb#L1-L45](lib/sfl/core/types/retrieval_filters.rb#L1-L45), [db/migrations/011_add_parent_clause_id_to_clauses.rb#L1-L83](db/migrations/011_add_parent_clause_id_to_clauses.rb#L1-L83)

## Related Types

| Type | Relationship |
|------|--------------|
| [SyntacticClause](11-pass-1-syntactic-parsing) | The structural core of `AnnotatedClause#syntactic`; carries tokens, groups, readability. |
| [IdeationalPayload](16-ideational-payload) | The Pass-1 metafunction payload inside `AnnotatedClause#ideational`. |
| [InterpersonalPayload](17-interpersonal-payload) | The Pass-2 metafunction payload inside `AnnotatedClause#interpersonal`. |
| [TextualPayload] | The Pass-2 textual metafunction payload inside `AnnotatedClause#textual` (optional). |
| [AnnotationResult] | The intermediate output of Pass 2 that feeds `interpersonal` and `textual` into `build_annotated_clause`. |
| [ConversationTurn] | Aggregates `AnnotatedClause[]` into a turn-shaped struct for analysis. |
| [AnalysisResult] | The final analysis artifact containing turns with `AnnotatedClause` arrays. |
| [RetrievalResult] | A ranked view of a clause with inline mood/tenor/process_type — deliberately not the full `AnnotatedClause`. |
| [GraphNode] | A lightweight summary of `AnnotatedClause` for the graph API. |

Sources: [lib/sfl/core/types/annotated_clause.rb#L1-L21](lib/sfl/core/types/annotated_clause.rb#L1-L21), [lib/sfl/core/types/syntactic_clause.rb#L1-L24](lib/sfl/core/types/syntactic_clause.rb#L1-L24), [lib/sfl/core/types/conversation_turn.rb#L1-L27](lib/sfl/core/types/conversation_turn.rb#L1-L27), [lib/sfl/core/types/analysis_result.rb#L1-L23](lib/sfl/core/types/analysis_result.rb#L1-L23), [lib/sfl/core/types/retrieval_result.rb#L1-L44](lib/sfl/core/types/retrieval_result.rb#L1-L44), [lib/sfl/core/types/graph_node.rb#L1-L24](lib/sfl/core/types/graph_node.rb#L1-L24)

## Next Steps

- For the syntactic foundation inside every clause, see [SyntacticClause & SyntacticToken](11-pass-1-syntactic-parsing) and [Ideational Payload](16-ideational-payload).
- For the annotation dimensions, see [Interpersonal Payload](17-interpersonal-payload) and [Textual Payload].
- For how clauses are stored and queried at scale, see [Database Schema](18-database-schema) and [Hybrid Retrieval with RRF](20-hybrid-retrieval-with-rrf).
- For how clauses enter the review cycle, see [Review Queues](29-review-queues).