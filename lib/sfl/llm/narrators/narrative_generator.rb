# frozen_string_literal: true

module SFL
  module LLM
    module Narrators
      # Calls the LLM to write the six-section interpretive narrative —
      # the `narrator:` duck Analysis::NarrativeGenerator requires
      # (`#call(digest_text) -> Hash` of its SECTION_KEYS), the same role
      # Synthesizers::ContextSynthesizer plays for
      # Retrieval::ContextSynthesizer. Replaces legacy's DSPy-backed
      # SFLNarrator/multi-model Achilles-Tortoise-Genie variant (track
      # decision 7 drops DSPy entirely; no multi-model verification pass
      # is ported — a single structured-output call, same shape as Pass 2
      # and context synthesis).
      class NarrativeGenerator
        # @param chat [#with_schema] a RubyLLM::Chat (or compatible double)
        def initialize(chat:)
          @chat = chat
        end

        # @param digest_text [String] Analysis::NarrativeGenerator::Digest#to_text
        # @return [Hash] symbol-keyed, one entry per
        #   Analysis::NarrativeGenerator::SECTION_KEYS
        def call(digest_text)
          prompt = Prompts.render(:narrative_generation, digest_text:)
          response = chat.with_schema(Schemas::NarrativeSchema).ask(prompt)
          ResponseSymbolizer.call(response.content)
        end

        attr_reader :chat
        private :chat
      end
    end
  end
end
