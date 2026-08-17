# SFL Engine — Architecture & Data Schema Catalog

| System Component | SFL Metafunction | Pipeline Stage | Output/Payload Type | Persistence Target |
|---|---|---|---|---|
| `SpacySidecarParser` | Ideational (pre) | Pass 1 | `SyntacticClause` (tokens, groups, root_index, sentence_index) | Transient (in-memory) |
| `IdeationalExtractor` | Ideational | Pass 1 | `IdeationalPayload` (process_type, participants, circumstances, raw_transitivity) | Transient (paired with clause) |
| `LLM::Engine` (via `ClauseAnnotator`/`BatchClauseAnnotator`) | Interpersonal | Pass 2 | `InterpersonalPayload` (mood, modality_weight, tenor, speaker_attitude, reasoning, reasoning_trace) | `interpersonal_payloads` table |
| `LLM::Engine` (via `ClauseAnnotator`/`BatchClauseAnnotator`) | Textual | Pass 2 | `TextualPayload` (topical_theme, textual_theme, interpersonal_theme, rheme, theme_type) | Transient (optional, not persisted separately) |
| `Pipeline#build_annotated_clause` | All three | Pass 1 + 2 | `AnnotatedClause` (id, text, syntactic, ideational, interpersonal, textual, document_id, compiled_at) | `clauses` + `ideational_payloads` + `interpersonal_payloads` tables |
| `PgClauseStore#replace_document` | All three (write) | Persistence | `void` (write) / `Array<AnnotatedClause>` (read via `find`, `find_by_document`, `find_all`) | `clauses`, `ideational_payloads`, `interpersonal_payloads` (PostgreSQL) |
| `PgEmbeddingStore#replace_document` | Textual (derivative) | Persistence | `void` (write) / `Hash<String, Array<Float>>` (read) | `embeddings` table (pgvector, 768-dim vectors) |
| `Embedder` / `LLM::Embedder` | Textual (derivative) | Persistence | `Array<Float>` per clause (single) / `Array<Array<Float>>` (batch) | `embeddings.embedding` column (pgvector) |
| `PgHybridRetriever#retrieve` | All three (read) | Retrieval | `Array<RetrievalResult>` (rrf_score, mood, tenor, modality_weight, process_type, annotation_source) | Joins: `embeddings` ↔ `clauses` ↔ `interpersonal_payloads` ↔ `ideational_payloads` |
| `ContextSynthesizer#synthesize` | All three (read) | Retrieval + Synthesis | `SynthesisResult` (answer, cited_clause_ids, clauses, confidence) | Transient (returns to caller) |
| `RetrievalFilters` | Interpersonal + Ideational (filter) | Retrieval | `RetrievalFilters` (mood, min/max_modality, min/max_tenor, process_type, source_type) | N/A (applied in `PgHybridRetriever` query scope) |
| `RetrievalQuery` | All three (query) | Retrieval | `RetrievalQuery` (query string, limit, filters) | N/A (input to `Retriever#retrieve`) |
