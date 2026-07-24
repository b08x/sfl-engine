# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Aggregated profile for a single speaker across a conversation.
      class SpeakerProfile < Dry::Struct
        attribute :speaker_name, Types::String
        attribute :turn_count, Types::Integer
        attribute :avg_tenor, Types::Float.constrained(gteq: 0.0, lteq: 1.0)
        attribute :tenor_range, Types::Array.of(Types::Float).constrained(size: 2)
        attribute :tenor_variance, Types::Float.constrained(gteq: 0.0)
        attribute :avg_modality, Types::Float.constrained(gteq: 0.0, lteq: 1.0)
        attribute :mood_distribution, Types::Hash.default({}.freeze)
        attribute :dominant_processes, Types::Hash.default({}.freeze)
      end
    end
  end
end
