# frozen_string_literal: true

require "dspy"

module SFL
  module LLM
    # Real Core::Ports::Classifier adapter: sends a file sample to an LLM
    # constrained by Signatures::ClassificationSignature.
    class Classifier
      include Core::Ports::Classifier

      # @param lm [DSPy::LM]
      # @param breaker [#call] Core::Ports::Breaker-compatible
      # @param logger [#debug,#info,#warn,#error] Core::Ports::Logger-compatible
      def initialize(lm:, breaker: Core::Ports::Null::Breaker.new, logger: Core::Ports::Null::Logger.new)
        @lm = lm
        @breaker = breaker
        @logger = logger

        @predictor = DSPy::Predict.new(Signatures::ClassificationSignature).tap do |p|
          p.configure { |c| c.lm = lm }
        end
      end

      # @param sample [String]
      # @param path [String] the file's original path
      # @return [Core::Types::ClassificationResult]
      def classify(sample, path)
        raw = breaker.call("classifier.classify") { fetch(sample, path) }
        Core::Types::ClassificationResult.new(
          format: raw.fetch(:format), mode: raw.fetch(:mode), confidence: raw.fetch(:confidence), reasoning: raw.fetch(:reasoning)
        )
      rescue => e
        logger.warn { "ingest classifier failed: #{e.class}: #{e.message}" }
        Core::Types::ClassificationResult.new(
          format: "unknown", mode: nil, confidence: 0.0, reasoning: "Classification failed: #{e.message}"
        )
      end

      attr_reader :lm, :breaker, :logger, :predictor
      private :lm, :breaker, :logger, :predictor

      private def fetch(sample, path)
        result = predictor.call(path:, sample:)
        result.to_h
      end
    end
  end
end
