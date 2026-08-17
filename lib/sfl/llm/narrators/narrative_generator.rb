# frozen_string_literal: true

require "dspy"

module SFL
  module LLM
    module Narrators
      # Calls the LLM to write the six-section interpretive narrative —
      # the `narrator:` duck Analysis::NarrativeGenerator requires
      class NarrativeGenerator
        # @param lm [DSPy::LM] The language model configuration for this task
        def initialize(lm:)
          @lm = lm
          @predictor = DSPy::Predict.new(Signatures::NarrativeSignature).tap do |p|
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
