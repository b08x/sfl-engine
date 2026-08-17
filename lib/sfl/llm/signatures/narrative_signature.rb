# frozen_string_literal: true

require "dspy"

module SFL
  module LLM
    module Signatures
      # Structured-output contract for Analysis::NarrativeGenerator's
      # narrator: duck (`#call(digest_text) -> Hash` of
      # Analysis::NarrativeGenerator::SECTION_KEYS) — one string field per
      # section, mirrored 1:1 against that constant so a future section
      # added there has an obvious matching field to add here.
      class NarrativeSignature < DSPy::Signature
        description "Generate a synthesized narrative from the provided analysis digest."

        input do
          const :digest, String, description: "A structured digest summarizing the conversational data"
        end

        output do
          const :overview, String, description: "1-2 paragraph summary of what this conversation/document is about"
          const :cast_and_roles, String, description: "Who the participants/sections are and the role each plays"
          const :interpersonal_dynamics, String, description: "Tenor/mood/modality patterns and what they reveal"
          const :conversational_arc, String, description: "How the conversation/document develops over its course"
          const :data_quality, String, description: "Caveats about fallback/stub annotations or low-confidence sections"
          const :takeaways, String, description: "The most important, citation-grounded conclusions"
        end
      end
    end
  end
end
