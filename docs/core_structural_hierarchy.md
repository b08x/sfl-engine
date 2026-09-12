# Module: SFL::Core
## Class: Pipeline
* Method: initialize | [pass_one, pass_two, ideational_extractor, clause_store, embedding_store, embedder, cache, logger, instrumenter] -> [Pipeline]
* Operation: Assigns injected dependencies to instance variables for end-to-end processing and storage orchestration.
* Method: call | [text, document_id, resume, store, embed, semantic_coherence_score, pass_one_only] -> [Result]
* Operation: Executes pass_one parsing, extracts ideational payloads, runs pass_two annotations via cache, persists to clause_store, generates embeddings, logs metrics, and returns a Monadic Result.
* Method: parse | [text, document_id] -> [Result]
* Operation: Calls pass_one.process and captures PassOne::Error to return a Monadic Failure instead of raising an exception.
* Method: pair_with_ideational | [clauses] -> [Array]
* Operation: Iterates over parsed clauses, extracting the ideational payload for each, and maps them into clause and ideational tuples.
* Method: annotate | [pairs, document_id, resume, semantic_coherence_score, pass_one_only] -> [Result]
* Operation: Evaluates flags to route execution to stub annotations, uncached batch annotations, or cache-backed annotations.
* Method: stub_annotate_all | [pairs] -> [Array]
* Operation: Uses a Null Annotator to generate stub batch results and returns constructed AnnotatedClause models.
* Method: annotate_all | [pairs, semantic_coherence_score] -> [Array]
* Operation: Wraps the pass_two batch annotation call with telemetry instrumentation and contextual parameters.
* Method: annotate_with_cache | [pairs, document_id, semantic_coherence_score] -> [Array]
* Operation: Computes SHA256 keys, partitions cache hits, validates trusted annotation sources, annotates cache misses, persists new trusted results, and reconstructs the ordered list.
* Method: fresh_annotations | [keyed, miss_keys, semantic_coherence_score] -> [Hash]
* Operation: Filters for missing keys, batches missing pairs through annotate_all, caches new responses from trusted sources, and indexes by key.
* Method: cache_key_for | [document_id, clause] -> [String]
* Operation: Generates a cryptographic hash using document ID, sentence index, and clause text to prevent positional collisions.
* Method: build_annotated_clause | [clause, ideational, annotation_result] -> [AnnotatedClause]
* Operation: Merges textual and interpersonal payload metadata, propagating untrusted status flags, and returns an instantiated AnnotatedClause entity.
* Method: persist | [annotated, document_id, store] -> [Result]
* Operation: Checks if storage is enabled; if so, atomically replaces the document's clauses in the PostgreSQL store via clause_store.replace_document.
* Method: embed_all | [annotated, document_id, embed] -> [Result]
* Operation: Checks if embedding is enabled; if so, batches embeddings through the embedder and replaces vectors in the embedding_store.
* Method: log_completion | [document_id, result, started_at] -> [UNDEFINED]
* Operation: Calculates elapsed latency, logging clause counts and timing breakdown on success, or failure inspection on failure.
* Method: now | [] -> [Float]
* Operation: Reads Process::CLOCK_MONOTONIC for elapsed time measurement.

# Module: SFL::Analysis
## Class: Engine
* Method: initialize | [pipeline, review_queue_repo, topic_modeler_factory, on_progress, on_turn_start, stop_requested, logger] -> [Engine]
* Operation: Retains core pipeline components, topic modeling factory configurations, event callback hooks, and custom adapters for isolated processing.
* Method: analyze | [source, label, store, resume, topics, pass_one_only] -> [AnalysisResult]
* Operation: Resolves execution options, fits the topic model using requested allocations, compiles conversational turns in a loop, and finalizes processing into a cross-turn derivation result.
* Method: build_result | [turns, source, label, total, interrupted, topic_labels, topic_shifts] -> [AnalysisResult]
* Operation: Sequences a series of analytical steps (artifacts chunking, tenor tracking, cohesion analysis, speaker profiling, correlation generation) into a comprehensive AnalysisResult entity.
* Method: topic_shift_moments | [topic_shifts] -> [Array]
* Operation: Iterates over identified topic shifts, extracting keys, and instantiating explicit KeyMoment payload structures.

# Module: SFL::Boot
## Class: UNDEFINED
* Method: call | [env_path, tty, input, kwargs] -> [Result]
* Operation: Loads Dotenv, validates provider API keys, connects to the Postgres database, initializes LLM and embedding configs, maps the Python sidecar path, optionally configures Langfuse tracing, and constructs the core Pipeline execution chain.
* Method: pass_two_task_config | [name, env] -> [TaskConfig]
* Operation: Fetches environment variables to build the specific TaskConfig dictionary for language model execution.
* Method: validate_api_keys! | [config, env] -> [UNDEFINED]
* Operation: Iterates over each distinct provider listed in the config and validates that the required API key exists in the environment, raising an error otherwise.
* Method: build_embedder | [llm_config, env] -> [Embedder]
* Operation: Extracts embedding target configs and instantiates the Embedder port, explicitly associating timeouts and circuit breaker constraints.
* Method: configure_tracing | [env, tty, input] -> [UNDEFINED]
* Operation: Prompts tracing reachability if configured. Raises an error on operator cancellation or registers Langfuse telemetry context.
* Method: connect_db | [env] -> [Sequel::Database]
* Operation: Establishes a Sequel Postgres connection, executes database pgvector extensions, and maps underlying driver failures to Boot::Error.
* Method: resolve_pass1_command | [spacy_model] -> [Array]
* Operation: Checks filesystem for vendored python path; returns a custom subprocess command array if present or returns nil to force sidecar defaults.

# Module: SFL::Core::PassOne
## Class: SpacySidecarParser
* Method: initialize | [model, command, env, logger] -> [SpacySidecarParser]
* Operation: Binds transport options for the NDJSON subprocess, initializes a synchronization Mutex, and executes start_process for the Python sidecar.
* Method: parse | [text, document_id] -> [Array]
* Operation: Synchronizes thread access, executes request, and maps JSON clause outputs to strongly typed SyntacticClause arrays.
* Method: close | [] -> [UNDEFINED]
* Operation: Synchronizes the shutdown lock and executes stop_process to cleanly tear down the Python background thread.
* Method: start_process | [] -> [UNDEFINED]
* Operation: Spawns the Python command in a dedicated OS process group, captures IO streams, and blocks execution awaiting the JSON ready signal.
* Method: await_ready | [] -> [UNDEFINED]
* Operation: Blocks process reading from stdout within a timeout block until a predefined JSON ready payload is emitted from the sidecar.
* Method: request | [text, document_id, retried] -> [Array]
* Operation: Transmits unstructured text to sidecar stdin, reads JSON from stdout, and catches broken pipe anomalies for automated single-cycle failover restarts.
* Method: fail_or_retry | [text, document_id, error, retried] -> [Array]
* Operation: Escalates a SidecarError if a retry is exhausted; otherwise, triggers process restart and executes request with the retried flag.
* Method: read_response | [] -> [Hash]
* Operation: Calls blocking IO on stdout and parses the resulting text into a Ruby Hash, raising errors for premature pipe termination.
* Method: write_line | [payload] -> [UNDEFINED]
* Operation: Marshals the dictionary payload into JSON and dispatches it over stdin, mapping system IO failures to domain SidecarErrors.
* Method: restart_process | [] -> [UNDEFINED]
* Operation: Wraps execution of stop_process and start_process sequentially to refresh the Python subprocess.
* Method: stop_process | [] -> [UNDEFINED]
* Operation: Attempts explicit closure of stdin/stdout handles and joins the OS process waiting thread, swallowing native IO exceptions safely.
* Method: build_clauses | [clause_hashes] -> [Array]
* Operation: Iterates across nested clause maps, mapping tokens into SyntacticToken entries and enclosing them within SyntacticClause definitions.
