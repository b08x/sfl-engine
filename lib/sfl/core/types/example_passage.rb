# frozen_string_literal: true

module SFL
  module Core
    module Types
      # An example passage cited for a specific rhetorical stance.
      class ExamplePassage < Dry::Struct
        attribute :label, Types::String
        attribute :text, Types::String
        attribute :speaker, Types::String
        attribute :value, Types::Float
        attribute :reason, Types::String
      end
    end
  end
end
