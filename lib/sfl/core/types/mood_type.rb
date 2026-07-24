# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Mood types from SFL — canonical values come from ClassificationRegistry
      # so the type constraint and the fuzzy-normalization dimension can never
      # drift apart.
      MoodType = String.enum(*ClassificationRegistry.canonical_values(:mood))
    end
  end
end
