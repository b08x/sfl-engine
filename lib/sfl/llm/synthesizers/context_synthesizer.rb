# frozen_string_literal: true

require "dspy"

module SFL
  module LLM
    module Synthesizers
      # Calls the LLM for evidence-grounded query synthesis
      class ContextSynthesizer
        # @param lm [DSPy::LM] The language model configuration for this task
        def initialize(lm:)
          @lm = lm
          @predictor = DSPy::Predict.new(Signatures::SynthesisSignature).tap do |p|
            p.configure { |c| c.lm = lm }
          end
        end

        # @param query [String]
        # @param evidence [String] numbered clauses with text and SFL annotations
        # @return [Hash] :answer, :cited_clause_numbers, :confidence — symbol-keyed
        def call(query:, evidence:)
          result = @predictor.call(query:, evidence:)
          ResponseSymbolizer.call(result.to_h)
        end

        private

        attr_reader :lm
      end
    end
  end
end
