# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # Editor that returns the text unchanged.
        class Editor
          include Ports::Editor

          def edit(text) = text
        end
      end
    end
  end
end
