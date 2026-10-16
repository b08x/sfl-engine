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
          flesch: report.flesch,
          kincaid: report.kincaid,
          fog: report.fog,
          word_count: report.num_words
        )
      end
    end
  end
end
