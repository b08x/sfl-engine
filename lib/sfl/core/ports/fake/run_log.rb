# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Fake
        # In-memory RunLog with an injectable clock and pid-liveness seam.
        class RunLog
          include Ports::RunLog

          attr_reader :rows

          # @param clock [#call] returns the current Time
          # @param alive [#call] pid -> Boolean
          # @param stall_after [Numeric] seconds
          def initialize(clock: -> { Time.now }, alive: RunState::PID_ALIVE, stall_after: RunState::STALL_AFTER_SECONDS)
            @clock = clock
            @alive = alive
            @stall_after = stall_after
            @rows = {}
          end

          def start(run_id:, kind:, collection:, total:, pid:, models: nil)
            now = @clock.call
            @rows[run_id] = {
              run_id:,
              kind:,
              collection:,
              total:,
              pid:,
              models:,
              status: "running",
              done: 0,
              failed: 0,
              current_item: nil,
              started_at: now,
              heartbeat_at: now,
              finished_at: nil,
            }
            nil
          end

          def advance(run_id, **fields)
            @rows.fetch(run_id).merge!(fields, heartbeat_at: @clock.call)
            nil
          end

          def heartbeat(run_id) = advance(run_id)

          def finish(run_id, status:)
            @rows.fetch(run_id).merge!(status:, finished_at: @clock.call)
            nil
          end

          def list(limit: 50)
            now = @clock.call
            @rows.values.sort_by { |row| row[:started_at] }.reverse.first(limit).map do |row|
              row.merge(state: RunState.classify(row, now:, stall_after: @stall_after, alive: @alive))
            end
          end

          def stalled = list(limit: @rows.size).select { |row| RunState::STALLED.include?(row[:state]) }
        end
      end
    end
  end
end
