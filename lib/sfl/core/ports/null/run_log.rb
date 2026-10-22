# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # No-op RunLog: records nothing and lists no runs.
        class RunLog
          include Ports::RunLog

          def start(run_id:, kind:, collection:, total:, pid:, models: nil) # rubocop:disable Lint/UnusedMethodArgument -- RunLog port contract
            nil
          end

          def advance(_run_id, **_fields) = nil
          def heartbeat(_run_id) = nil
          def finish(_run_id, status:) = nil # rubocop:disable Lint/UnusedMethodArgument -- RunLog port contract
          def list(limit: 50) = [] # rubocop:disable Lint/UnusedMethodArgument -- RunLog port contract
          def stalled = []
        end
      end
    end
  end
end
