# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Fake
        # Editor that records what it was given and returns a fixed result.
        class Editor
          include Ports::Editor

          attr_reader :edited

          # @param result [String, #call] the edited text, or text -> edited text
          def initialize(result: nil)
            @result = result
            @edited = []
          end

          def edit(text)
            @edited << text
            return text if @result.nil?

            @result.respond_to?(:call) ? @result.call(text) : @result
          end
        end
      end
    end
  end
end
