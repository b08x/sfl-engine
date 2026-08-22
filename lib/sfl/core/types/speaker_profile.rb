# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Aggregated profile for a single speaker across a conversation.
      #
      # The four tenor/modality aggregates are nilable on purpose: when none
      # of a speaker's turns carry a trusted (llm/human) annotation there is
      # no aggregate to report, and the only honest answer is absence. A
      # fabricated 0.5 midpoint in that slot is indistinguishable from a real
      # "perfectly mixed" measurement — that substitution is exactly what made
      # a total Pass 2 failure look like a finished analysis.
      class SpeakerProfile < Dry::Struct
        attribute :speaker_name, Types::String
        attribute :turn_count, Types::Integer
        attribute :avg_tenor, Types::Float.constrained(gteq: 0.0, lteq: 1.0).optional
        attribute :tenor_range, Types::Array.of(Types::Float).constrained(size: 2).optional
        attribute :tenor_variance, Types::Float.constrained(gteq: 0.0).optional
        attribute :avg_modality, Types::Float.constrained(gteq: 0.0, lteq: 1.0).optional
        attribute :mood_distribution, Types::Hash.default({}.freeze)
        attribute :dominant_processes, Types::Hash.default({}.freeze)
      end
    end
  end
end
