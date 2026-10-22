# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # No-op ProgressSink: nothing is listening.
        class ProgressSink
          include Ports::ProgressSink

          def start(_total)
            nil
          end

          def advance(by: 1, failed: 0) # rubocop:disable Lint/UnusedMethodArgument -- by and failed stay in the signature to match the ProgressSink port contract
            nil
          end

          def finish(status: "finished") # rubocop:disable Lint/UnusedMethodArgument -- ProgressSink port contract
            nil
          end
        end
      end
    end
  end
end
