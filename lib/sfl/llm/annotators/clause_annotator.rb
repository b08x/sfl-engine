# frozen_string_literal: true

module SFL
  module LLM
    module Annotators
      # Calls the LLM for a single clause's Pass 2 annotation. Takes a
      # structured context Hash built directly from Types objects by the
      # caller (SFL::LLM::Engine) — never a formatted string it has to
      # re-parse. This is the I3 fix: the legacy SFLAnnotator#parse_context
      # existed only because the engine handed it a pre-formatted string;
      # here there's no string boundary to cross in the first place.
      class ClauseAnnotator
        # @param chat [#with_schema] a RubyLLM::Chat (or compatible double)
        def initialize(chat:)
          @chat = chat
        end

        # @param context [Hash] :text, :root_verb, :process_type, :participants, :pos_tags,
        #   :dependencies, :semantic_coherence_score (optional) — see
        #   lib/sfl/prompts/templates/pass_two_annotation.txt.erb for the exact shape
        # @return [Hash] raw annotation fields, symbol-keyed
        def call(context)
          prompt = Prompts.render(:pass_two_annotation, **context)
          response = chat.with_schema(Schemas::ClauseAnnotationSchema).ask(prompt)
          ResponseSymbolizer.call(response.content)
        end

        private

        attr_reader :chat
      end
    end
  end
end
