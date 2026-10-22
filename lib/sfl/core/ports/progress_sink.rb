# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Reports pipeline progress to whatever surface is listening (the runs
      # table, the foreground dashboard).
      module ProgressSink
        # @param total [Integer]
        # @return [void]
        def start(total)
          raise NotImplementedError, "#{self.class} must implement #start"
        end

        # @param by [Integer] items finished
        # @param failed [Integer] of those, items that failed
        # @return [void]
        def advance(by: 1, failed: 0)
          raise NotImplementedError, "#{self.class} must implement #advance"
        end

        # @param status [String] "finished", "failed" or "interrupted"
        # @return [void]
        def finish(status: "finished")
          raise NotImplementedError, "#{self.class} must implement #finish"
        end
      end
    end
  end
end
