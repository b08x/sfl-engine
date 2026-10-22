# frozen_string_literal: true

require "sequel"

module SFL
  module Store
    # Postgres RunLog over the `runs` table (migrations 017 and 020), keyed by
    # SFL_RUN_ID. #list and #stalled classify each row with Core::RunState,
    # using the injected clock and pid-liveness seam.
    class PgRunRepository
      include Core::Ports::RunLog

      FIELDS = %i[total done failed current_item].freeze

      # @param db [Sequel::Database]
      # @param clock [#call] returns the current Time
      # @param alive [#call] pid -> Boolean
      # @param stall_after [Numeric] seconds
      def initialize(db, clock: -> { Time.now }, alive: Core::RunState::PID_ALIVE,
        stall_after: Core::RunState::STALL_AFTER_SECONDS
      )
        @db = db
        @clock = clock
        @alive = alive
        @stall_after = stall_after
      end

      def start(run_id:, kind:, collection:, total:, pid:, models: nil)
        raise ArgumentError, "kind must be one of #{KINDS.join(', ')}" unless KINDS.include?(kind)

        now = @clock.call
        row = {
          kind:,
          collection:,
          total:,
          pid:,
          models: models && Sequel.pg_jsonb(models),
          status: "running",
          done: 0,
          failed: 0,
          current_item: nil,
          started_at: now,
          heartbeat_at: now,
          finished_at: nil,
        }
        runs.insert_conflict(target: :run_id, update: row).insert(row.merge(run_id:))
        nil
      end

      def advance(run_id, **fields)
        runs.where(run_id:).update(fields.slice(*FIELDS).merge(heartbeat_at: @clock.call))
        nil
      end

      def heartbeat(run_id) = advance(run_id)

      def finish(run_id, status:)
        now = @clock.call
        runs.where(run_id:).update(status:, finished_at: now, heartbeat_at: now)
        nil
      end

      def list(limit: 50)
        now = @clock.call
        runs.reverse(:started_at).limit(limit).all.map do |row|
          row.merge(state: Core::RunState.classify(row, now:, stall_after: @stall_after, alive: @alive))
        end
      end

      def stalled
        now = @clock.call
        runs.where(status: "running").reverse(:started_at).all.filter_map do |row|
          state = Core::RunState.classify(row, now:, stall_after: @stall_after, alive: @alive)
          row.merge(state:) if Core::RunState::STALLED.include?(state)
        end
      end

      private def runs = @db[:runs]
    end
  end
end
