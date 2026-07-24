# frozen_string_literal: true

module SFL
  module Retrieval
    # Answers a natural-language query from previously stored clauses:
    # hybrid retrieval (RRF + scalar stance filters) feeds a numbered,
    # SFL-annotated evidence block to an LLM synthesis call. Citations
    # come back as evidence numbers and are mapped to clause ids here —
    # out-of-range numbers are dropped (don't trust LLM references).
    #
    # Ports the legacy Compiler::ContextSynthesizer (track decision 7 drops
    # its DSPy synthesizer for a ruby_llm-schema one, LLM::Synthesizers::
    # ContextSynthesizer, mirroring Annotators::ClauseAnnotator's role for
    # Pass 2). No clause_repo/N+1 enrichment step here — PgHybridRetriever
    # already inlines mood/tenor/process_type/modality_weight/
    # annotation_source onto every Core::Types::RetrievalResult row (see
    # that struct's own comment), so there is nothing left to enrich.
    class ContextSynthesizer
      # rubocop:disable Metrics/ParameterLists -- retriever plus the same three cross-cutting
      # ports every LLM-calling class in this codebase takes (see LLM::Engine), plus the
      # chat:/synthesizer: fallback-lambda pair mirroring legacy's own synthesizer: nil default.
      def initialize(
        retriever:,
        chat: nil,
        synthesizer: nil,
        breaker: Core::Ports::Null::Breaker.new,
        instrumenter: Core::Ports::Null::Instrumenter.new,
        logger: Core::Ports::Null::Logger.new
      )
        @retriever = retriever
        @synthesizer = synthesizer || (chat && LLM::Synthesizers::ContextSynthesizer.new(chat:))
        raise ArgumentError, "must provide chat: or explicit synthesizer:" unless @synthesizer

        @breaker = breaker
        @instrumenter = instrumenter
        @logger = logger
      end
      # rubocop:enable Metrics/ParameterLists

      # @param query [String]
      # @param filters [Hash] RetrievalFilters attributes
      #   (:mood, :min_tenor, :max_tenor, :min_modality, :max_modality, :process_type, :source_type)
      # @param limit [Integer]
      # @param include_fallback [Boolean] When false (default), clauses
      #   whose interpersonal annotation came from the Pass 2 degradation
      #   ladder (annotation_source "fallback"/"stub") are excluded from
      #   what the LLM sees and from what citations can reference — a
      #   fallback 0.5 shouldn't silently ground an answer. They still
      #   appear in `clauses:` (the full retrieved set is always reported).
      # @return [Core::Types::SynthesisResult]
      def synthesize(query, filters: {}, limit: 10, include_fallback: false)
        rows = retriever.retrieve(build_retrieval_query(query, filters, limit))
        return empty_result(query) if rows.empty?

        clauses = rows.map(&:to_h)
        citable, preamble = partition_citable(rows, include_fallback)
        return excluded_result(query, preamble, clauses, rows.size) if citable.empty?

        synthesize_from_citable(query, citable, clauses, rows.size, preamble)
      end

      attr_reader :retriever, :synthesizer, :breaker, :instrumenter, :logger
      private :retriever, :synthesizer, :breaker, :instrumenter, :logger

      private def build_retrieval_query(query, filters, limit)
        Core::Types::RetrievalQuery.new(query:, limit:, filters: Core::Types::RetrievalFilters.new(**filters))
      end

      private def empty_result(query)
        Core::Types::SynthesisResult.new(query:, answer: nil, retrieved_count: 0, confidence: nil)
      end

      private def excluded_result(query, preamble, clauses, retrieved_count)
        Core::Types::SynthesisResult.new(query:, answer: preamble, clauses:, retrieved_count:, confidence: nil)
      end

      # Splits ranked rows into what the LLM may see/cite vs what's
      # excluded for carrying a fallback/stub interpersonal annotation,
      # and the Data Quality preamble describing that split (nil when
      # nothing was excluded).
      private def partition_citable(rows, include_fallback)
        citable = include_fallback ? rows : rows.select { |row| llm_sourced?(row) }
        [citable, data_quality_preamble(rows.size - citable.size, rows.size)]
      end

      # Unlike Pass 2, a failed synthesis call propagates — there is no
      # useful default "answer".
      private def synthesize_from_citable(query, citable, clauses, retrieved_count, preamble)
        output = fetch_synthesis(query, citable)
        cited = map_citations(output[:cited_clause_numbers], citable)

        Core::Types::SynthesisResult.new(
          query:, answer: prepend_data_quality(output[:answer], preamble),
          cited_clause_ids: cited.uniq, clauses:,
          retrieved_count:, confidence: output[:confidence]
        )
      rescue Dry::Struct::Error => e
        degraded_result(query, clauses, retrieved_count, e)
      end

      private def fetch_synthesis(query, citable)
        instrumenter.instrument("context_synthesis.synthesize", clause_count: citable.size) do
          breaker.call("context_synthesis.synthesize") do
            synthesizer.call(query:, evidence: format_evidence(citable))
          end
        end
      end

      private def degraded_result(query, clauses, retrieved_count, error)
        logger.warn do
          "context_synthesis (#{query}): invalid synthesizer output: #{error.message} " \
            "— returning evidence without an answer"
        end
        Core::Types::SynthesisResult.new(
          query:, answer: nil, clauses:,
          retrieved_count:, confidence: nil
        )
      end

      private def map_citations(numbers, citable)
        Array(numbers).filter_map { |number| citable[number - 1]&.clause_id if number.positive? }
      end

      # Defensively treats a missing/nil annotation_source (rows stored
      # before this column existed) as trusted rather than excluding them.
      # "human" counts as trusted alongside "llm" — a reviewer-supplied
      # correction is not a compiler-substituted default.
      private def llm_sourced?(row)
        source = row.annotation_source
        source.nil? || Core::Types::TRUSTED_ANNOTATION_SOURCES.include?(source)
      end

      private def data_quality_preamble(excluded_count, total_count)
        return nil if excluded_count.zero?

        "_Data Quality: #{excluded_count}/#{total_count} retrieved clauses excluded due to fallback annotation._"
      end

      private def prepend_data_quality(answer, preamble)
        return answer unless preamble

        "#{preamble}\n\n#{answer}"
      end

      private def format_evidence(citable)
        citable.each_with_index.map do |row, idx|
          annotations = [
            "mood=#{row.mood}",
            "tenor=#{row.tenor}",
            "modality=#{row.modality_weight}",
            "process=#{row.process_type}",
          ].join(", ")

          "[#{idx + 1}] #{row.text}\n    (#{annotations}; source: #{row.document_id})"
        end.join("\n")
      end
    end
  end
end
