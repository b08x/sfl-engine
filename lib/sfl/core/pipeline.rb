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
    # section," not the whole app's composition root (that's Boot, still
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

      # rubocop:disable Metrics/ParameterLists -- ten independently-injectable collaborators:
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
        instrumenter: Ports::Null::Instrumenter.new,
        readability_scorer: Analysis::ReadabilityScorer.new,
        section_registry: Ports::Null::SectionRegistry.new
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
        @readability_scorer = readability_scorer
        @section_registry = section_registry
      end
      # rubocop:enable Metrics/ParameterLists

      # @param text [String]
      # @param section_id [String, nil]
      # @param unit [Types::Unit, nil] the loader unit being compiled; when given with
      #   store: true, the SectionRegistry records its document and section in the same
      #   transaction as the clause replacement
      # @param store [Boolean] persist annotated clauses via ClauseStore
      # @param embed [Boolean] compute and persist embeddings (requires section_id)
      # @param resume [Boolean] serve Pass 2 results from Cache where available (requires section_id)
      # @param semantic_coherence_score [Float, nil] forwarded to Pass 2 as extra context
      # @param pass_one_only [Boolean] skip Pass 2 entirely and stub every clause's
      #   interpersonal/textual payloads via Ports::Null::Annotator instead (mood:
      #   "declarative", modality_weight/tenor: 0.5, annotation_source: "stub"). This is the
      #   single, structural fix for the documentation golden-master bug (see
      #   spec/fixtures/golden_master/README.md): legacy had two independently-maintained
      #   copies of "should I run Pass 2 or stub it" — ConversationAnalyzer branched on it,
      #   DocumentationAnalyzer silently didn't — and the second one drifted. Living here
      #   instead of in Analysis::Engine/per-Source means there is exactly one implementation
      #   for every future caller to inherit correctly, not N.
      # @return [Dry::Monads::Result] Success(Array<Types::AnnotatedClause>) or
      #   Failure([:pass_one_failed, message])
      # rubocop:disable Metrics/ParameterLists
      # Pipeline#compile's own options exactly (store/embed/resume/semantic_coherence_score),
      # plus pass_one_only (see above); the five-stage bind chain is the ladder itself, not
      # something to fragment further.
      def compile(text, section_id: nil, unit: nil, store: true, embed: true, resume: false,
        semantic_coherence_score: nil, pass_one_only: false
      )
        logger.debug("pipeline started", section_id:, text_length: text.length)
        started_at = now

        result = parse(text, section_id)
          .bind { |clauses| Success(pair_with_ideational(clauses)) }
          .bind { |pairs| annotate(pairs, section_id, resume, semantic_coherence_score, pass_one_only) }
          .bind { |annotated| persist(annotated, section_id, store, unit) }
          .bind { |annotated| embed_all(annotated, section_id, embed) }

        log_completion(section_id, result, started_at)
        result
      end
      # rubocop:enable Metrics/ParameterLists

      attr_reader :pass_one, :pass_two, :ideational_extractor, :clause_store, :embedding_store,
        :embedder, :cache, :logger, :instrumenter, :readability_scorer, :section_registry
      private :pass_one, :pass_two, :ideational_extractor, :clause_store, :embedding_store,
        :embedder, :cache, :logger, :instrumenter, :readability_scorer, :section_registry

      private def parse(text, section_id)
        Success(pass_one.process(text, section_id:))
      rescue PassOne::Error => e
        logger.error("pipeline pass_one failed", section_id:, error_class: e.class, error_message: e.message)
        Failure([:pass_one_failed, e.message])
      end

      private def pair_with_ideational(clauses)
        clauses.map { |clause| [clause, ideational_extractor.extract(clause)] }
      end

      private def annotate(pairs, section_id, resume, semantic_coherence_score, pass_one_only)
        return Success(stub_annotate_all(pairs)) if pass_one_only
        return Success(annotate_all(pairs, semantic_coherence_score)) unless resume && section_id

        Success(annotate_with_cache(pairs, section_id, semantic_coherence_score))
      end

      # Reuses Ports::Null::Annotator rather than re-literalizing its stub
      # InterpersonalPayload/TextualPayload values here — one source of
      # truth for "what does a stubbed annotation look like" whether it's
      # reached via pass_one_only: true or via DI-ing Null::Annotator in
      # directly as pass_two.
      private def stub_annotate_all(pairs)
        results = Ports::Null::Annotator.new.annotate_batch(pairs)
        pairs.zip(results).map { |(clause, ideational), result| build_annotated_clause(clause, ideational, result) }
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
      private def annotate_with_cache(pairs, section_id, semantic_coherence_score)
        keyed = pairs.map { |clause, ideational| [cache_key_for(section_id, clause), clause, ideational] }
        hits, miss_keys = cache.partition(keyed.map { |key, _clause, _ideational| key })

        # Self-heal poisoned caches: treat untrusted cache entries as misses
        trusted_hits = hits.select do |_, clause|
          Types::TRUSTED_ANNOTATION_SOURCES.include?(clause.interpersonal.annotation_source)
        end
        miss_keys += (hits.keys - trusted_hits.keys)
        hits = trusted_hits

        fresh_by_key = fresh_annotations(keyed, miss_keys, semantic_coherence_score)

        logger.info("pipeline cache", section_id:, hits: hits.size, misses: miss_keys.size)
        keyed.map { |key, _clause, _ideational| hits[key] || fresh_by_key.fetch(key) }
      end

      private def fresh_annotations(keyed, miss_keys, semantic_coherence_score)
        misses = keyed.select { |key, _clause, _ideational| miss_keys.include?(key) }
        return {} if misses.empty?

        annotated = annotate_all(misses.map do |_key, clause, ideational|
          [clause, ideational]
        end, semantic_coherence_score)

        misses.zip(annotated).to_h do |(key, _clause, _ideational), annotated_clause|
          cache.write(key, annotated_clause) if Types::TRUSTED_ANNOTATION_SOURCES.include?(annotated_clause.interpersonal.annotation_source)
          [key, annotated_clause]
        end
      end

      # sentence_index disambiguates clauses with identical text recurring
      # at different positions in the same section (e.g. repeated
      # boilerplate headers) — without it they'd collide on one cache key.
      private def cache_key_for(section_id, clause)
        Digest::SHA256.hexdigest("#{section_id}#{clause.sentence_index}#{clause.text}")
      end

      private def build_annotated_clause(clause, ideational, annotation_result)
        interpersonal = annotation_result.interpersonal
        interpersonal = Types::InterpersonalPayload.new(interpersonal.to_h.merge(untrusted: true)) if annotation_result.textual&.untrusted
        clause = Types::SyntacticClause.new(clause.to_h.merge(readability: readability_scorer.score(clause.text)))

        Types::AnnotatedClause.new(
          id: SecureRandom.uuid,
          text: clause.text,
          syntactic: clause,
          ideational:,
          interpersonal:,
          textual: annotation_result.textual,
          section_id: clause.section_id,
          compiled_at: Time.now,
          untrusted: annotation_result.interpersonal.untrusted || annotation_result.textual&.untrusted == true
        )
      end

      private def persist(annotated, section_id, store, unit)
        return Success(annotated) unless store && section_id

        logger.debug("persisting clauses to database", section_id:, clause_count: annotated.size)
        section_registry.transaction do
          clause_store.replace_section(section_id, annotated)
          section_registry.register(unit, annotated.size) if unit
        end
        Success(annotated)
      end

      # Requires section_id to scope the EmbeddingStore replace, same as
      # ClauseStore — an embed run with no section_id has nothing to
      # replace idempotently on a re-run, so it's skipped rather than
      # writing embeddings nothing can look back up.
      #
      # Embeds leaves only — clauses no other clause's parent_clause_id
      # points at — so vectors live at chunk granularity, not duplicated up
      # every ancestor. Until a future chunk-splitting pass populates
      # parent_clause_id, every clause is a leaf, so this is a no-op today.
      private def embed_all(annotated, section_id, embed)
        return Success(annotated) unless embed && section_id && !annotated.empty?

        leaves = leaf_clauses(annotated)
        logger.debug("generating embeddings", section_id:, clause_count: leaves.size)
        vectors = embedder.embed_batch(leaves.map(&:text))
        embeddings_by_clause_id = leaves.zip(vectors).to_h { |ac, vector| [ac.id, vector] }
        embedding_store.replace_section(section_id, embeddings_by_clause_id)

        Success(annotated)
      end

      private def leaf_clauses(annotated)
        parent_ids = annotated.filter_map { |c| c.syntactic.parent_clause_id }.to_set
        annotated.reject { |c| parent_ids.include?(c.id) }
      end

      private def log_completion(section_id, result, started_at)
        elapsed_ms = ((now - started_at) * 1000).round(2)

        if result.success?
          clause_count = result.value!.size
          logger.info("pipeline completed", section_id:, clause_count:, latency_ms: elapsed_ms)
          # Serialize once per completed pipeline, not once per Pass 2 batch:
          # report_json walks every accumulated span, so logging it inside
          # annotate_batch made long multi-turn runs repeatedly serialize the
          # entire history and added avoidable work to the measured path.
          logger.info("pass_two timing_breakdown", timing_breakdown: instrumenter.report_json) if instrumenter.respond_to?(:report_json)
        else
          logger.error("pipeline failed", section_id:, failure: result.failure.inspect)
        end
      end

      private def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
