# frozen_string_literal: true

require "time"

module SFL
  module LLM
    # Pass 2 use case: maps syntactic structures onto SFL interpersonal
    # and textual metafunctions via an LLM. Implements Ports::Annotator so
    # the pipeline never depends on ruby_llm directly.
    #
    # Replaces the legacy DSPy-based PassTwoEngine (track decision 7):
    # no provider-fallback chain, no CognitiveGas/rolling-synthesis
    # machinery (that belonged to the quarantined GEB sprint jobs, which
    # track decision 12 explicitly drops) — one provider per Engine
    # instance, one Breaker around each call, truthful "fallback"
    # provenance on any rejection (Degradation), and contract rejection
    # instead of clamp01 scale-guessing (F6/D9): an out-of-range
    # modality_weight/tenor is a Dry::Struct::Error this class catches
    # and degrades from, never silently rescaled.
    # rubocop:disable Metrics/ClassLength -- Pass 2's contract-rejection/degradation logic
    # (interpersonal_from, textual_from, reasoning_trace_from, and their WARN wiring) is one
    # conceptual unit; Degradation/DerivationHash/ResponseSymbolizer/the schemas/the annotators
    # are already split into their own files, this is what's left after that split.
    class Engine
      include Core::Ports::Annotator

      # rubocop:disable Metrics/ParameterLists -- six independently-injectable collaborators
      # (an annotator pair, and the three cross-cutting ports every Engine in this codebase
      # takes), each named for exactly what it replaces in a test double.
      def initialize(
        chat: nil,
        clause_annotator: nil,
        batch_clause_annotator: nil,
        breaker: Core::Ports::Null::Breaker.new,
        instrumenter: Core::Ports::Null::Instrumenter.new,
        logger: Core::Ports::Null::Logger.new
      )
        @clause_annotator = clause_annotator || (chat && Annotators::ClauseAnnotator.new(chat:))
        @batch_clause_annotator = batch_clause_annotator || (chat && Annotators::BatchClauseAnnotator.new(chat:))
        raise ArgumentError, "must provide chat: or explicit clause_annotator:/batch_clause_annotator:" \
          unless @clause_annotator && @batch_clause_annotator

        @breaker = breaker
        @instrumenter = instrumenter
        @logger = logger
      end
      # rubocop:enable Metrics/ParameterLists

      # @param clause [SFL::Core::Types::SyntacticClause]
      # @param ideational [SFL::Core::Types::IdeationalPayload]
      # @param context [Hash] optional :semantic_coherence_score
      # @return [SFL::Core::Types::AnnotationResult]
      def annotate(clause, ideational, context: {})
        logger.debug { "pass_two started (clause_id=#{clause.id})" }
        started_at = now

        result = annotation_result_for(clause, fetch_single(clause, ideational, context))
        log_completion(clause, result, started_at)
        result
      rescue => e
        log_failure(clause, e)
        default_result(clause, "LLM call failed: #{e.message}")
      end

      # @param pairs [Array<[SFL::Core::Types::SyntacticClause, SFL::Core::Types::IdeationalPayload]>]
      # @param context [Hash] optional :semantic_coherence_score, applied to every pair
      # @return [Array<SFL::Core::Types::AnnotationResult>] same order as pairs
      def annotate_batch(pairs, context: {})
        return [] if pairs.empty?

        raw_by_index = fetch_batch(pairs, context)

        pairs.each_with_index.map do |(clause, _ideational), index|
          raw = raw_by_index[index]
          next annotation_result_for(clause, raw) if raw

          logger.warn { "pass_two missing annotation for clause #{clause.id} (index #{index}) — defaults applied" }
          default_result(clause, "No annotation returned for this clause — defaults applied")
        end
      end

      attr_reader :clause_annotator, :batch_clause_annotator, :breaker, :instrumenter, :logger
      private :clause_annotator, :batch_clause_annotator, :breaker, :instrumenter, :logger

      private def fetch_single(clause, ideational, context)
        instrumenter.instrument("pass_two.annotate", clause_id: clause.id) do
          breaker.call("pass_two.annotate") { clause_annotator.call(build_context(clause, ideational, context)) }
        end
      end

      # rubocop:disable Metrics/AbcSize -- context-building (index/instrument/breaker) plus
      # index-keying the response is one pipeline step; splitting it further would scatter
      # a single request/response round trip across method boundaries.
      private def fetch_batch(pairs, context)
        contexts = pairs.each_with_index.map do |(clause, ideational), index|
          build_context(clause, ideational, context).merge(index:)
        end

        raw = instrumenter.instrument("pass_two.annotate_batch", clause_count: pairs.size) do
          breaker.call("pass_two.annotate_batch") { batch_clause_annotator.call(contexts) }
        end
        raw.to_h { |entry| [entry[:index], entry] }
      rescue => e
        logger.warn { "pass_two batch failed (#{e.message}) — defaults applied to #{pairs.size} clauses" }
        {}
      end
      # rubocop:enable Metrics/AbcSize

      # rubocop:disable Metrics/AbcSize -- six independent Hash entries built from clause/
      # ideational data; each is a one-line map/join already extracted as far as it reasonably
      # goes (root_verb_for is the one that had real branching logic to pull out).
      private def build_context(clause, ideational, extra)
        {
          text: clause.text,
          root_verb: root_verb_for(clause),
          process_type: ideational.process_type,
          participants: ideational.participants.map { |p| "#{p.role}: #{p.text}" }.join(", "),
          pos_tags: clause.tokens.map { |t| "#{t.text}/#{t.pos}" }.join(" "),
          dependencies: clause.tokens.map { |t| "#{t.text}<#{t.dep}" }.join(" "),
          semantic_coherence_score: extra[:semantic_coherence_score],
        }
      end
      # rubocop:enable Metrics/AbcSize

      private def root_verb_for(clause)
        root = clause.tokens[clause.root_index]
        return "unknown" unless root

        "#{root.text} (lemma: #{root.lemma}, pos: #{root.pos}, tag: #{root.tag})"
      end

      private def annotation_result_for(clause, raw)
        interpersonal = interpersonal_from(clause, raw)
        textual = textual_from(clause, raw)

        Core::Types::AnnotationResult.new(
          interpersonal: interpersonal || Degradation.default_interpersonal(
            clause.id, reason: "Invalid interpersonal values — defaults applied"
          ),
          textual: textual || Degradation.default_textual(clause.id)
        )
      end

      # rubocop:disable Metrics/MethodLength -- normalize + log + build a seven-attribute
      # struct is the same three-step shape textual_from uses; nothing left to extract that
      # conclusion_for/safe_reasoning_trace_from haven't already pulled out.
      private def interpersonal_from(clause, raw)
        mood, status = Core::ClassificationRegistry.normalize(:mood, raw[:mood])
        log_classification_gap(:mood, status, raw[:mood], mood, clause)
        conclusion = conclusion_for(mood, raw)

        Core::Types::InterpersonalPayload.new(
          clause_id: clause.id,
          mood:,
          modality_weight: raw[:modality_weight],
          tenor: raw[:tenor],
          speaker_attitude: raw[:speaker_attitude],
          reasoning: raw[:reasoning],
          annotation_source: "llm",
          reasoning_trace: safe_reasoning_trace_from(raw, conclusion, clause)
        )
      rescue Dry::Struct::Error => e
        logger.warn { "pass_two invalid interpersonal for clause #{clause.id}: #{e.message} — defaults applied" }
        nil
      end
      # rubocop:enable Metrics/MethodLength

      private def conclusion_for(mood, raw)
        {
          mood:,
          modality_weight: raw[:modality_weight],
          tenor: raw[:tenor],
          speaker_attitude: raw[:speaker_attitude],
        }
      end

      # A malformed reasoning trace must never default the clause's actual
      # mood/tenor/modality — those came back correctly from the LLM;
      # only the provenance layer is at risk. Guarded separately from
      # interpersonal_from so one bad premise can't default the whole
      # clause, only its reasoning_trace.
      private def safe_reasoning_trace_from(raw, conclusion, clause)
        reasoning_trace_from(raw, conclusion)
      rescue Dry::Struct::Error => e
        logger.warn do
          "pass_two invalid reasoning_trace for clause #{clause.id}: #{e.message} — reasoning_trace left nil"
        end
        nil
      end

      # rubocop:disable Metrics/MethodLength -- one struct literal, six required attributes
      private def reasoning_trace_from(raw, conclusion)
        premises = (raw[:premises] || []).map do |p|
          Core::Types::Premise.new(type: p[:type], source: p[:source], value: p[:value], weight: p[:weight])
        end
        inference_rule = raw[:inference_rule] || "unknown"

        Core::Types::ReasoningTrace.new(
          premises:,
          inference_rule:,
          conclusion:,
          confidence: raw[:confidence] || 0.5,
          derivation_hash: DerivationHash.compute(premises:, inference_rule:, conclusion:),
          generated_at: Time.now
        )
      end
      # rubocop:enable Metrics/MethodLength

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- normalize + log + construct is
      # the same three-step shape as interpersonal_from; splitting it further than that
      # (already-extracted) shared shape would fragment one classification-then-build step.
      private def textual_from(clause, raw)
        theme_type, status = Core::ClassificationRegistry.normalize(:theme_type, raw[:theme_type])
        log_classification_gap(:theme_type, status, raw[:theme_type], theme_type, clause)

        Core::Types::TextualPayload.new(
          clause_id: clause.id,
          topical_theme: raw[:topical_theme] || clause.text.split.first,
          textual_theme: raw[:textual_theme],
          interpersonal_theme: raw[:interpersonal_theme],
          rheme: raw[:rheme],
          theme_type:
        )
      rescue Dry::Struct::Error => e
        logger.warn { "pass_two invalid textual for clause #{clause.id}: #{e.message} — defaults applied" }
        nil
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      private def default_result(clause, reason)
        Core::Types::AnnotationResult.new(
          interpersonal: Degradation.default_interpersonal(clause.id, reason:),
          textual: Degradation.default_textual(clause.id)
        )
      end

      # Shared WARN wiring for both ClassificationRegistry dimensions
      # (mood in interpersonal_from, theme_type in textual_from).
      # :unknown means the value fell through to the default — a real
      # schema gap. :fuzzy means Jaro-Winkler resolved a near-miss to a
      # real category — the value is good, but it still gets surfaced so
      # the alias table can gain a permanent entry instead of paying the
      # fuzzy scan on every future run.
      private def log_classification_gap(dimension, status, raw_value, resolved, clause)
        return unless %i[unknown fuzzy].include?(status)

        logger.warn do
          "pass_two #{status} #{dimension} for clause #{clause.id}: '#{raw_value}' -> '#{resolved}'" \
            "#{' (unrecognized value, consider adding it to ClassificationRegistry)' if status == :unknown}"
        end
      end

      private def log_completion(clause, result, started_at)
        elapsed_ms = ((now - started_at) * 1000).round(2)
        logger.info do
          "pass_two completed (clause_id=#{clause.id}, mood=#{result.interpersonal.mood}, " \
            "tenor=#{result.interpersonal.tenor}, modality_weight=#{result.interpersonal.modality_weight}, " \
            "latency_ms=#{elapsed_ms})"
        end
      end

      private def log_failure(clause, error)
        logger.error { "pass_two failed (clause_id=#{clause.id}): #{error.class}: #{error.message}" }
      end

      private def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
