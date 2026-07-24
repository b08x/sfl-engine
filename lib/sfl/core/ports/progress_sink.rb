# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Reports pipeline progress to whatever surface is listening (CLI
      # progress bar, GUI progress control, chat agent status message).
      module ProgressSink
        # @param total [Integer]
        # @return [void]
        def start(total)
          raise NotImplementedError, "#{self.class} must implement #start"
        end

        # @param by [Integer]
        # @return [void]
        def advance(by: 1)
          raise NotImplementedError, "#{self.class} must implement #advance"
        end

        # @return [void]
        def finish
          raise NotImplementedError, "#{self.class} must implement #finish"
        end
      end
    end
  end
end
