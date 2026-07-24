# frozen_string_literal: true

require "dry/monads"
require "securerandom"
require "digest"

module SFL
  module Core
    # Composes Pass 1 (a SyntacticParser + IdeationalExtractor) and Pass 2
    # (an Annotator) into the end-to-end compile use case, plus optional
    # storage and embedding. Nothing else in this codebase wires these
    # pieces together — Pipeline is the composition point for "compile a
    # document," not the whole app's composition root (that's Boot, still
    # Phase 4 work).
    #
    # No GC.start: the legacy Pipeline swept dead PyCall wrappers by hand
    # before Pass 2, dodging a GIL/GVL deadlock risk if GC ran on a Pass 2
    # worker thread instead (D1). The Python sidecar (track decision 2)
    # means Pass 1 no longer shares the Ruby process at all — there is no
    # PyCall object graph left for GC to trip over, so the workaround is
    # obsolete, not ported.
    #
    # dry-monads Result ladder: each stage returns Success/Failure and
    # #bind only runs the next stage on Success, so a Pass 1 failure
    # short-circuits straight past ideational extraction, Pass 2, storage,
    # and embedding — no explicit guard needed at every step.
    # rubocop:disable Metrics/ClassLength -- one use case (compile) with five pipeline stages,
    # each already its own private method; the class is the sum of those five stages plus the
    # constructor, not one long method.
    class Pipeline
      include Dry::Monads[:result]

      # rubocop:disable Metrics/ParameterLists -- nine independently-injectable collaborators:
      # the two required engines, plus every optional port this pipeline touches, each named
      # for exactly what it replaces in a test double (matches the pattern already used by
      # PassOne::Engine and LLM::Engine).
      def initialize(
        pass_one:,
        pass_two:,
        ideational_extractor: PassOne::IdeationalExtractor.new,
        clause_store: Ports::Null::ClauseStore.new,
        embedding_store: Ports::Null::EmbeddingStore.new,
        embedder: Ports::Null::Embedder.new,
        cache: Ports::Null::Cache.new,
        logger: Ports::Null::Logger.new,
        instrumenter: Ports::Null::Instrumenter.new
      )
        @pass_one = pass_one
        @pass_two = pass_two
        @ideational_extractor = ideational_extractor
        @clause_store = clause_store
        @embedding_store = embedding_store
        @embedder = embedder
        @cache = cache
        @logger = logger
        @instrumenter = instrumenter
      end
      # rubocop:enable Metrics/ParameterLists

      # @param text [String]
      # @param document_id [String, nil]
      # @param store [Boolean] persist annotated clauses via ClauseStore
      # @param embed [Boolean] compute and persist embeddings (requires document_id)
      # @param resume [Boolean] serve Pass 2 results from Cache where available (requires document_id)
      # @param semantic_coherence_score [Float, nil] forwarded to Pass 2 as extra context
      # @return [Dry::Monads::Result] Success(Array<Types::AnnotatedClause>) or
      #   Failure([:pass_one_failed, message])
      # rubocop:disable Metrics/ParameterLists, Metrics/AbcSize -- mirrors the legacy
      # Pipeline#compile's own options exactly (store/embed/resume/semantic_coherence_score);
      # the five-stage bind chain is the ladder itself, not something to fragment further.
      def compile(text, document_id: nil, store: true, embed: true, resume: false, semantic_coherence_score: nil)
        logger.debug { "pipeline started (document_id=#{document_id.inspect}, text_length=#{text.length})" }
        started_at = now

        result = parse(text, document_id)
          .bind { |clauses| Success(pair_with_ideational(clauses)) }
          .bind { |pairs| annotate(pairs, document_id, resume, semantic_coherence_score) }
          .bind { |annotated| persist(annotated, document_id, store) }
          .bind { |annotated| embed_all(annotated, document_id, embed) }

        log_completion(document_id, result, started_at)
        result
      end
      # rubocop:enable Metrics/ParameterLists, Metrics/AbcSize

      attr_reader :pass_one, :pass_two, :ideational_extractor, :clause_store, :embedding_store,
        :embedder, :cache, :logger, :instrumenter
      private :pass_one, :pass_two, :ideational_extractor, :clause_store, :embedding_store,
        :embedder, :cache, :logger, :instrumenter

      private def parse(text, document_id)
        Success(pass_one.process(text, document_id:))
      rescue PassOne::Error => e
        logger.error { "pipeline pass_one failed (document_id=#{document_id.inspect}): #{e.message}" }
        Failure([:pass_one_failed, e.message])
      end

      private def pair_with_ideational(clauses)
        clauses.map { |clause| [clause, ideational_extractor.extract(clause)] }
      end

      private def annotate(pairs, document_id, resume, semantic_coherence_score)
        return Success(annotate_all(pairs, semantic_coherence_score)) unless resume && document_id

        Success(annotate_with_cache(pairs, document_id, semantic_coherence_score))
      end

      private def annotate_all(pairs, semantic_coherence_score)
        context = { semantic_coherence_score: }
        results = instrumenter.instrument("pipeline.annotate", clause_count: pairs.size) do
          pass_two.annotate_batch(pairs, context:)
        end
        pairs.zip(results).map { |(clause, ideational), result| build_annotated_clause(clause, ideational, result) }
      end

      # Cache#partition returns hit values in the same call that identifies
      # them as hits (see the Cache port contract) — the fix for F10, where
      # the legacy PipelineCache#partition/compile_with_cache pair read
      # every hit from disk twice: once inside partition to decide hit vs.
      # miss, once more afterward to rebuild the original clause order.
      private def annotate_with_cache(pairs, document_id, semantic_coherence_score)
        keyed = pairs.map { |clause, ideational| [cache_key_for(document_id, clause), clause, ideational] }
        hits, miss_keys = cache.partition(keyed.map { |key, _clause, _ideational| key })
        fresh_by_key = fresh_annotations(keyed, miss_keys, semantic_coherence_score)

        logger.info { "pipeline cache (document_id=#{document_id}): #{hits.size} hits, #{miss_keys.size} misses" }
        keyed.map { |key, _clause, _ideational| hits[key] || fresh_by_key.fetch(key) }
      end

      private def fresh_annotations(keyed, miss_keys, semantic_coherence_score)
        misses = keyed.select { |key, _clause, _ideational| miss_keys.include?(key) }
        return {} if misses.empty?

        annotated = annotate_all(misses.map do |_key, clause, ideational|
          [clause, ideational]
        end, semantic_coherence_score)

        misses.zip(annotated).to_h do |(key, _clause, _ideational), annotated_clause|
          cache.write(key, annotated_clause)
          [key, annotated_clause]
        end
      end

      # sentence_index disambiguates clauses with identical text recurring
      # at different positions in the same document (e.g. repeated
      # boilerplate headers) — without it they'd collide on one cache key.
      private def cache_key_for(document_id, clause)
        Digest::SHA256.hexdigest("#{document_id}#{clause.sentence_index}#{clause.text}")
      end

      private def build_annotated_clause(clause, ideational, annotation_result)
        Types::AnnotatedClause.new(
          id: SecureRandom.uuid,
          text: clause.text,
          syntactic: clause,
          ideational:,
          interpersonal: annotation_result.interpersonal,
          textual: annotation_result.textual,
          document_id: clause.document_id,
          compiled_at: Time.now
        )
      end

      private def persist(annotated, document_id, store)
        return Success(annotated) unless store && document_id

        clause_store.replace_document(document_id, annotated)
        Success(annotated)
      end

      # Requires document_id to scope the EmbeddingStore replace, same as
      # ClauseStore — an embed run with no document_id has nothing to
      # replace idempotently on a re-run, so it's skipped rather than
      # writing embeddings nothing can look back up.
      private def embed_all(annotated, document_id, embed)
        return Success(annotated) unless embed && document_id && !annotated.empty?

        vectors = embedder.embed_batch(annotated.map(&:text))
        embeddings_by_clause_id = annotated.zip(vectors).to_h { |ac, vector| [ac.id, vector] }
        embedding_store.replace_document(document_id, embeddings_by_clause_id)

        Success(annotated)
      end

      private def log_completion(document_id, result, started_at)
        elapsed_ms = ((now - started_at) * 1000).round(2)

        if result.success?
          clause_count = result.value!.size
          logger.info do
            "pipeline completed (document_id=#{document_id.inspect}, clause_count=#{clause_count}, " \
              "latency_ms=#{elapsed_ms})"
          end
        else
          logger.error { "pipeline failed (document_id=#{document_id.inspect}): #{result.failure.inspect}" }
        end
      end

      private def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
