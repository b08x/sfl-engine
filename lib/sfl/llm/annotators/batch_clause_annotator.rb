# frozen_string_literal: true

require "dspy"

module SFL
  module LLM
    module Annotators
      # Calls the LLM once for many clauses' Pass 2 annotations — the
      # batched counterpart to ClauseAnnotator.
      class BatchClauseAnnotator
        # @param lm [DSPy::LM] The language model configuration for this task
        def initialize(lm:)
          @lm = lm
          @predictor = DSPy::Predict.new(Signatures::BatchClauseAnnotationSignature).tap do |p|
            p.configure { |c| c.lm = lm }
          end
        end

        # @param contexts [Array<Hash>] each a :index plus the same keys ClauseAnnotator takes
        # @return [Array<Hash>] one Hash per annotation the LLM returned, symbol-keyed
        def call(contexts)
          result = @predictor.call(clauses: contexts)
          ResponseSymbolizer.call(result.to_h).fetch(:annotations)
        end

        private

        attr_reader :lm
      end
    end
  end
end
