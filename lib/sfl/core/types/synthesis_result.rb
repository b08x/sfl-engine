# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Result of a context query: hybrid retrieval + LLM synthesis.
      class SynthesisResult < Dry::Struct
        attribute :query, Types::String
        attribute :answer, Types::String.optional
        attribute :cited_clause_ids, Types::Array.of(Types::String).default([].freeze)
        attribute :clauses, Types::Array.of(Types::Hash).default([].freeze)
        attribute :retrieved_count, Types::Integer
        attribute :confidence, Types::Float.optional
      end
    end
  end
end
