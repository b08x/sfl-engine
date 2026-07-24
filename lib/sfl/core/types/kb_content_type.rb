# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Content-type enum for KnowledgeBaseSource artifacts (default
      # :unknown for unclassified sections) — ported from legacy
      # Types::KBContentType verbatim.
      KBContentType = Coercible::Symbol.default(:unknown).enum(
        :research_note, :technical_reference, :tutorial, :draft,
        :ai_generated, :code_snippet, :index, :image, :unknown
      )
    end
  end
end
