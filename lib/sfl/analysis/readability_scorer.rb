# frozen_string_literal: true

require "lingua"

module SFL
  module Analysis
    # Thin wrapper around Lingua::EN::Readability — the single seam so
    # callers never touch the `lingua` gem's API directly (mirrors how
    # LLM::Embedder wraps the Ollama HTTP call).
    class ReadabilityScorer
      # @param text [String]
      # @return [Core::Types::Readability]
      def score(text)
        report = Lingua::EN::Readability.new(text.to_s)

        Core::Types::Readability.new(
          flesch: finite_or_nil(report.flesch),
          kincaid: finite_or_nil(report.kincaid),
          fog: finite_or_nil(report.fog),
          word_count: report.num_words
        )
      end

      # The gem divides by its own zero word count for zero-word text
      # ("...", code fences, emoji), yielding NaN — which no downstream
      # consumer can use and JSON.generate rejects outright
      # (JSON::GeneratorError, the annotation-cache crash). nil is
      # Types::Readability's "not computable" value (every attribute is
      # Float.optional) and round-trips through the cache and the clauses
      # table unchanged.
      # @param score [Float]
      # @return [Float, nil]
      private def finite_or_nil(score)
        score.finite? ? score : nil
      end
    end
  end
end
