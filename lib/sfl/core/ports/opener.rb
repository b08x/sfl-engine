# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Opens a file in the desktop's external viewer.
      module Opener
        # @param path [String]
        # @return [void]
        def open(path)
          raise NotImplementedError, "#{self.class} must implement #open"
        end
      end
    end
  end
end
