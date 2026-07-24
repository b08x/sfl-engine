# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Participant in a transitivity process.
      class Participant < Dry::Struct
        attribute :role, Types::String
        attribute :text, Types::String
      end
    end
  end
end
