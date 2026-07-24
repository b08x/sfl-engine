# frozen_string_literal: true

module SFL
  module Core
    module Types
      # An LLM-written interpretive narrative over an analysis. Six fixed
      # prose sections; assembly into markdown is the formatter's job.
      class NarrativeReport < Dry::Struct
        attribute :source, Types::String
        attribute :generated_at, Types::Time
        attribute :overview, Types::String
        attribute :cast_and_roles, Types::String
        attribute :interpersonal_dynamics, Types::String
        attribute :conversational_arc, Types::String
        attribute :data_quality, Types::String
        attribute :takeaways, Types::String
      end
    end
  end
end
