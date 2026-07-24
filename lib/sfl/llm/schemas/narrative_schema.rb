# frozen_string_literal: true

require "ruby_llm/schema"

module SFL
  module LLM
    module Schemas
      # Structured-output contract for Analysis::NarrativeGenerator's
      # narrator: duck (`#call(digest_text) -> Hash` of
      # Analysis::NarrativeGenerator::SECTION_KEYS) — one string field per
      # section, mirrored 1:1 against that constant so a future section
      # added there has an obvious matching field to add here.
      class NarrativeSchema < RubyLLM::Schema
        string :overview, description: "1-2 paragraph summary of what this conversation/document is about"
        string :cast_and_roles, description: "Who the participants/sections are and the role each plays"
        string :interpersonal_dynamics, description: "Tenor/mood/modality patterns and what they reveal"
        string :conversational_arc, description: "How the conversation/document develops over its course"
        string :data_quality, description: "Caveats about fallback/stub annotations or low-confidence sections"
        string :takeaways, description: "The most important, citation-grounded conclusions"
      end
    end
  end
end
