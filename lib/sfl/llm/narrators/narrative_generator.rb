# frozen_string_literal: true

require "dspy"

module SFL
  module LLM
    module Narrators
      # Calls the LLM to write the six-section interpretive narrative —
      # the `narrator:` duck Analysis::NarrativeGenerator requires
      class NarrativeGenerator
        SIGNATURES = {
          v0: Signatures::NarrativeSignatureV0,
          v1: Signatures::NarrativeSignatureV1,
          v2: Signatures::NarrativeSignatureV2,
        }.freeze
        DEFAULT_VARIANT = :v1

        # @param lm [DSPy::LM] The language model configuration for this task
        # @param variant [Symbol] :v0 (one-line baseline, Predict), :v1 (sfl-compiler's
        #   signature, ChainOfThought) or :v2 (V1 plus grounding rules, ChainOfThought).
        #   Selected by SFL_NARRATIVE_VARIANT; see SFL::Boot.
        # @raise [ArgumentError] for an unknown variant
        def initialize(lm:, variant: DEFAULT_VARIANT)
          signature = SIGNATURES.fetch(variant) { raise ArgumentError, "unknown narrative variant #{variant.inspect}" }
          predictor_class = (variant == :v0) ? DSPy::Predict : DSPy::ChainOfThought
          @lm = lm
          @predictor = predictor_class.new(signature).tap do |p|
            p.configure { |c| c.lm = lm }
          end
        end

        # @param digest_text [String] Analysis::NarrativeGenerator::Digest#to_text
        # @return [Hash] symbol-keyed, one entry per
        #   Analysis::NarrativeGenerator::SECTION_KEYS
        def call(digest_text)
          result = @predictor.call(digest: digest_text)
          ResponseSymbolizer.call(result.to_h)
        end

        attr_reader :lm
        private :lm
      end
    end
  end
end
