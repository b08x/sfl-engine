# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Ideational metafunction payload (from Pass 1).
      class IdeationalPayload < Dry::Struct
        attribute :clause_id, Types::String
        attribute :process_type, Types::ProcessType
        attribute :participants, Types::Array.of(Participant) # Semantic roles
        attribute :circumstances, Types::Array.of(Types::String)  # Adjuncts
        attribute :raw_transitivity, Types::Hash                  # Full transitivity parse
      end
    end
  end
end
