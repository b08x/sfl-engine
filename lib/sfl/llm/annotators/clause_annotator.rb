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
        def initialize(lm:, instrumenter: Core::Ports::Null::Instrumenter.new)
          @lm = lm
          @instrumenter = instrumenter
          @predictor = DSPy::Predict.new(Signatures::ClauseAnnotationSignature).tap do |p|
            p.configure { |c| c.lm = lm }
          end
        end

        # @param context [Hash] :text, :root_verb, :process_type, :participants, :pos_tags,
        #   :dependencies, :semantic_coherence_score (optional)
        # @return [Hash] raw annotation fields, symbol-keyed
        def call(context)
          raw = instrumenter.instrument("pass_two.provider_request", provider: lm.class.name) do
            @predictor.call(**context)
          end
          serialized = instrumenter.instrument("pass_two.parse.deserialization") { raw.to_h }
          normalized = instrumenter.instrument("pass_two.parse.normalization") { ResponseSymbolizer.call(serialized) }
          instrumenter.instrument("pass_two.parse.classification") { normalized }
        end

        private

        attr_reader :lm, :instrumenter
      end
    end
  end
end
