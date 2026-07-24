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
        attribute :document_id, Types::String.optional
      end
    end
  end
end
