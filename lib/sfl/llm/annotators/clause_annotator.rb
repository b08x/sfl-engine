# frozen_string_literal: true

require "dspy"

module SFL
  module LLM
    module Annotators
      # Calls the LLM for a single clause's Pass 2 annotation. Takes a
      # structured context Hash built directly from Types objects by the
      # caller (SFL::LLM::Engine).
      class ClauseAnnotator
        # @param lm [DSPy::LM] The language model configuration for this task
        def initialize(lm:)
          @lm = lm
          @predictor = DSPy::Predict.new(Signatures::ClauseAnnotationSignature).tap do |p|
            p.configure { |c| c.lm = lm }
          end
        end

        # @param context [Hash] :text, :root_verb, :process_type, :participants, :pos_tags,
        #   :dependencies, :semantic_coherence_score (optional)
        # @return [Hash] raw annotation fields, symbol-keyed
        def call(context)
          result = @predictor.call(**context)
          ResponseSymbolizer.call(result.to_h)
        end

        private

        attr_reader :lm
      end
    end
  end
end
