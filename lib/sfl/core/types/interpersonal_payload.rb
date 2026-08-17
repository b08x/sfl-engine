# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Interpersonal metafunction payload (from Pass 2).
      class InterpersonalPayload < Dry::Struct
        attribute :clause_id, Types::String
        attribute :mood, Types::MoodType
        attribute :modality_weight, Types::ModalityWeight
        attribute :tenor, Types::TenorValue
        attribute :speaker_attitude, Types::String.optional
        attribute :reasoning, Types::String.optional
        attribute :annotation_source, Types::AnnotationSource
        attribute :reasoning_trace, ReasoningTrace.optional.default(nil)
        attribute :raw_classification, Types::String.optional.default(nil)
        attribute :classification_status, Types::ClassificationStatus.optional.default(nil)
        attribute :untrusted, Types::Bool.default(false)
      end
    end
  end
end
