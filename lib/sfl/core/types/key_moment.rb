# frozen_string_literal: true

module SFL
  module Core
    module Types
      # A notable moment in a conversation (tenor shift, topic shift, etc).
      class KeyMoment < Dry::Struct
        attribute :turn_id, Types::Integer
        attribute :type,
          Types::String.enum("tenor_shift", "modality_shift", "topic_shift", "semantic_anomaly", "deflation_anomaly")
        attribute :magnitude, Types::Float
        attribute :description, Types::String
      end
    end
  end
end
