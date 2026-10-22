# frozen_string_literal: true

module SFL
  module Core
    module Types
      # A clause with full syntactic tree from Pass 1.
      class SyntacticClause < Dry::Struct
        attribute(:id, Types::String.default { SecureRandom.uuid })
        attribute :text, Types::String
        attribute :tokens, Types::Array.of(SyntacticToken)
        attribute :groups, Types::Array.of(SyntacticGroup).default([].freeze)
        attribute :root_index, Types::Integer
        attribute :sentence_index, Types::Integer
        attribute :section_id, Types::String.optional
        # AnnotatedClause#id of the clause this one is a child chunk of, or
        # nil for a root/top-level clause (self-referential FK on `clauses`,
        # db/migrations/011_add_parent_clause_id_to_clauses.rb).
        attribute :parent_clause_id, Types::String.optional.default(nil)
        attribute :readability, Readability.optional.default(nil)
      end
    end
  end
end
