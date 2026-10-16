# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Lingua::EN::Readability scores for one clause's text — computed by
      # Analysis::ReadabilityScorer, persisted on SyntacticClause (the one
      # struct that actually round-trips through the `clauses` table).
      class Readability < Dry::Struct
        attribute :flesch, Types::Float.optional.default(nil)
        attribute :kincaid, Types::Float.optional.default(nil)
        attribute :fog, Types::Float.optional.default(nil)
        attribute :word_count, Types::Integer.optional.default(nil)
      end
    end
  end
end
