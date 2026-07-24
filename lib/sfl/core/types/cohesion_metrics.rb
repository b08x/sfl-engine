# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Cohesion metrics for a group of clauses.
      class CohesionMetrics < Dry::Struct
        attribute :repetition_score, Types::Float.constrained(gteq: 0.0, lteq: 1.0).default(0.0)
        attribute :conjunction_density, Types::Float.constrained(gteq: 0.0, lteq: 1.0).default(0.0)
        attribute :pronoun_density, Types::Float.constrained(gteq: 0.0, lteq: 1.0).default(0.0)
      end
    end
  end
end
