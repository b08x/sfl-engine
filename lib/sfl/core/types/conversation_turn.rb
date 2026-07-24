# frozen_string_literal: true

module SFL
  module Core
    module Types
      # A single turn in a conversation with SFL annotations.
      class ConversationTurn < Dry::Struct
        attribute :turn_id, Types::Integer
        attribute :speaker, Types::String
        attribute :timestamp, Types::Time
        attribute :message_text, Types::String
        attribute :clauses, Types::Array.of(AnnotatedClause)
        attribute :avg_tenor, Types::Float.constrained(gteq: 0.0, lteq: 1.0)
        attribute :avg_modality, Types::Float.constrained(gteq: 0.0, lteq: 1.0)
        attribute :dominant_mood, Types::MoodType
        attribute :process_types, Types::Hash.default({}.freeze)
        attribute :participants, Types::Array.of(Types::String).default([].freeze)
        attribute :tenor_shift, Types::Float.optional
        attribute :cohesion, CohesionMetrics.optional.default(nil)
        attribute :topic_distribution, Types::Hash.optional.default(nil)
        attribute :dominant_topic, Types::Integer.optional.default(nil)
        attribute :semantic_coherence_score, Types::Float.constrained(gteq: 0.0, lteq: 1.0).optional.default(nil)
      end
    end
  end
end
