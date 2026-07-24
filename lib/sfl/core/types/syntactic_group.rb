# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Group rank (SFL rank scale: Sentence > Clause > Group > Word >
      # Morpheme) — a nominal/verbal/adverbial/prepositional phrase, one
      # rank above Word and one below Clause. `token_indices` refers to a
      # parent SyntacticClause's `tokens` array by position, the same
      # indexing SyntacticToken#index and SyntacticClause#root_index use.
      class SyntacticGroup < Dry::Struct
        attribute(:id, Types::String.default { SecureRandom.uuid })
        attribute :type, Types::String.enum("nominal", "verbal", "adverbial", "prepositional")
        attribute :text, Types::String
        attribute :head_token_index, Types::Integer
        attribute :token_indices, Types::Array.of(Types::Integer)
      end
    end
  end
end
