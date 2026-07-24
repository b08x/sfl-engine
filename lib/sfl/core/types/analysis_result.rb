# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Complete analysis result for a conversation.
      class AnalysisResult < Dry::Struct
        attribute :metadata, Types::Hash
        attribute :turns, Types::Array.of(ConversationTurn)
        attribute :speaker_profiles, Types::Hash
        attribute :tenor_timeline, Types::Array.of(Types::Hash)
        attribute :field_evolution, Types::Array.of(Types::Hash)
        attribute :correlations, Types::Hash
        attribute :insights, Types::Array.of(Types::String)
        attribute :key_moments, Types::Array.of(KeyMoment).default([].freeze)
        attribute :example_passages, Types::Array.of(ExamplePassage).default([].freeze)
        attribute :topic_labels, Types::Hash.optional.default(nil)
        attribute :topic_evolution, Types::Array.of(Types::Hash).default([].freeze)
      end
    end
  end
end
