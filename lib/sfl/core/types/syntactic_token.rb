# frozen_string_literal: true

module SFL
  module Core
    module Types
      # A single token with syntactic annotations from Pass 1.
      class SyntacticToken < Dry::Struct
        attribute :text, Types::String
        attribute :lemma, Types::String
        attribute :pos, Types::String          # Coarse POS (e.g., "VERB", "NOUN")
        attribute :tag, Types::String          # Fine-grained POS (e.g., "VBG", "NNP")
        attribute :dep, Types::String          # Dependency relation (e.g., "nsubj", "ROOT")
        attribute :head_index, Types::Integer  # Index of head token (-1 for ROOT)
        attribute :morphology, Types::Hash.default({}.freeze)
        attribute :index, Types::Integer       # Position in sentence
      end
    end
  end
end
