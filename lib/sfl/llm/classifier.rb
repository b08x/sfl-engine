# frozen_string_literal: true

module SFL
  module LLM
    # Real Core::Ports::Classifier adapter: sends a file sample to an LLM
    # constrained by Schemas::ClassificationSchema, following the same
    # chat.with_schema(...).ask(...) shape already established by
    # Annotators::ClauseAnnotator/BatchClauseAnnotator.
    #
    # Deliberately does NOT raise on failure the way Embedder does. A
    # failed/timed-out call degrades to an explicit, provenance-tagged
    # confidence-0.0 "unknown" ClassificationResult instead of raising
    # SFL::LLM::Error — Ingest::Orchestrator (a later task) treats
    # "classifier says unknown/low-confidence" uniformly whether the cause
    # was a genuinely unrecognized format or an LLM outage, and the
    # degraded value is explicit/inspectable (reasoning carries the
    # failure message), not a silently-fabricated success value. This
    # still satisfies this codebase's no-silent-degradation rule (D9) —
    # it's a different sanctioned failure shape than Embedder's, not an
    # exception to it.
    class Classifier
      include Core::Ports::Classifier

      # @param chat [#with_schema] a RubyLLM::Chat (or compatible double)
      # @param breaker [#call] Core::Ports::Breaker-compatible
      # @param logger [#debug,#info,#warn,#error] Core::Ports::Logger-compatible
      def initialize(chat:, breaker: Core::Ports::Null::Breaker.new, logger: Core::Ports::Null::Logger.new)
        @chat = chat
        @breaker = breaker
        @logger = logger
      end

      # @param sample [String]
      # @param path [String] the file's original path — included in the prompt so the model
      #   can use the filename/extension as a classification signal, not just raw content
      # @return [Core::Types::ClassificationResult]
      def classify(sample, path)
        raw = breaker.call("classifier.classify") { fetch(sample, path) }
        Core::Types::ClassificationResult.new(
          format: raw[:format], mode: raw[:mode], confidence: raw[:confidence], reasoning: raw[:reasoning]
        )
      rescue => e
        logger.warn { "ingest classifier failed: #{e.class}: #{e.message}" }
        Core::Types::ClassificationResult.new(
          format: "unknown", mode: nil, confidence: 0.0, reasoning: "Classification failed: #{e.message}"
        )
      end

      attr_reader :chat, :breaker, :logger
      private :chat, :breaker, :logger

      private def fetch(sample, path)
        prompt = Prompts.render(:ingest_classification, path:, sample:)
        response = chat.with_schema(Schemas::ClassificationSchema).ask(prompt)
        ResponseSymbolizer.call(response.content)
      end
    end
  end
end
