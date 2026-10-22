# frozen_string_literal: true

module SFL
  module Core
    # Classifies a run row for display. A running row whose process no longer
    # exists is `dead`; a running row whose heartbeat is older than the stall
    # threshold is `stalled`; every other row keeps its stored status.
    module RunState
      STALL_AFTER_SECONDS = 30

      # States a reader shows as needing attention.
      STALLED = %w[stalled dead].freeze

      # Process.kill(0) seam: true while a process with this pid exists.
      PID_ALIVE = lambda do |pid|
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      # @param row [Hash] {status:, heartbeat_at:, pid:}
      # @param now [Time]
      # @param stall_after [Numeric] seconds
      # @param alive [#call] pid -> Boolean
      # @return [String] "dead", "stalled" or the stored status
      module_function def classify(row, now:, stall_after: STALL_AFTER_SECONDS, alive: PID_ALIVE)
        return row[:status] unless row[:status] == "running"
        return "dead" if row[:pid] && !alive.call(row[:pid])
        return "stalled" if now - row[:heartbeat_at] > stall_after

        "running"
      end
    end
  end
end
