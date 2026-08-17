# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Textual metafunction payload (from Pass 2).
      class TextualPayload < Dry::Struct
        attribute :clause_id, Types::String
        attribute :topical_theme, Types::String.optional
        attribute :textual_theme, Types::String.optional
        attribute :interpersonal_theme, Types::String.optional
        attribute :rheme, Types::String.optional
        attribute :theme_type,
          Types::String.enum(*ClassificationRegistry.canonical_values(:theme_type)).optional
        attribute :raw_classification, Types::String.optional.default(nil)
        attribute :classification_status, Types::ClassificationStatus.optional.default(nil)
        attribute :untrusted, Types::Bool.default(false)
      end
    end
  end
end
