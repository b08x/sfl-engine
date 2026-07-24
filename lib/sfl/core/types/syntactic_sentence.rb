# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Sentence rank — the unit directly above Clause. Reifies what's
      # otherwise only an implicit grouping (SyntacticClause#sentence_index)
      # into its own addressable object, since a sentence can contain
      # multiple clauses (coordination, subordination).
      class SyntacticSentence < Dry::Struct
        attribute(:id, Types::String.default { SecureRandom.uuid })
        attribute :index, Types::Integer
        attribute :text, Types::String
        attribute :clause_ids, Types::Array.of(Types::String)
        attribute :document_id, Types::String.optional
      end
    end
  end
end
