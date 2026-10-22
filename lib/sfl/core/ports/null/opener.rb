# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # Opener that does nothing.
        class Opener
          include Ports::Opener

          def open(_path) = nil
        end
      end
    end
  end
end
