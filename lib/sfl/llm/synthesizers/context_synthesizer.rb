# frozen_string_literal: true

module SFL
  module LLM
    module Synthesizers
      # Calls the LLM for evidence-grounded query synthesis — the LLM-facing
      # collaborator SFL::Retrieval::ContextSynthesizer delegates to, the
      # same role Annotators::ClauseAnnotator plays for Pass 2's Engine.
      # Replaces legacy's DSPy-backed SFLSynthesizer (track decision 7).
      class ContextSynthesizer
        # @param chat [#with_schema] a RubyLLM::Chat (or compatible double)
        def initialize(chat:)
          @chat = chat
        end

        # @param query [String]
        # @param evidence [String] numbered clauses with text and SFL annotations
        #   (see SFL::Retrieval::ContextSynthesizer#format_evidence)
        # @return [Hash] :answer, :cited_clause_numbers, :confidence — symbol-keyed
        def call(query:, evidence:)
          prompt = Prompts.render(:context_synthesis, query:, evidence:)
          response = chat.with_schema(Schemas::SynthesisSchema).ask(prompt)
          ResponseSymbolizer.call(response.content)
        end

        private

        attr_reader :chat
      end
    end
  end
end
