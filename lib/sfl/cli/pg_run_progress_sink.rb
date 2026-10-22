# frozen_string_literal: true

module SFL
  module CLI
    # ProgressSink that writes a run's progress to a Core::Ports::RunLog (the
    # `runs` table through Store::PgRunRepository), keyed by SFL_RUN_ID.
    #
    # #start(total) adds +total+ items: the first call creates the run row,
    # later calls (one per file in a multi-file run) raise its total. While the
    # run is open a background thread writes a heartbeat every
    # +heartbeat_every+ seconds, so a long turn does not read as stalled.
    class PgRunProgressSink
      include Core::Ports::ProgressSink

      HEARTBEAT_SECONDS = 5

      # plus the log it writes to and the heartbeat interval; no natural grouping.
      # @param run_log [Core::Ports::RunLog]
      # @param run_id [String] SFL_RUN_ID
      # @param kind [String] one of Core::Ports::RunLog::KINDS
      # @param collection [String, nil]
      # @param pid [Integer]
      # @param heartbeat_every [Numeric, nil] seconds; nil disables the heartbeat thread
      # @param models [Hash, nil] the run header's effective model per task (LLM::Config#header)
      # rubocop:disable-next Metrics/ParameterLists -- each is a distinct field of the run row
      def initialize(run_log:, run_id:, kind:, collection: nil, pid: Process.pid, heartbeat_every: HEARTBEAT_SECONDS,
        models: nil
      )
        @run_log = run_log
        @run_id = run_id
        @kind = kind
        @collection = collection
        @models = models
        @pid = pid
        @heartbeat_every = heartbeat_every
        @total = 0
        @done = 0
        @failed = 0
        @started = false
      end

      def start(total)
        @total += total
        return @run_log.advance(@run_id, total: @total) if @started

        @started = true
        @run_log.start(run_id: @run_id, kind: @kind, collection: @collection, total: @total, pid: @pid, models: @models)
        start_heartbeat
      end

      # @param by [Integer] items finished
      # @param failed [Integer] of those, items that failed
      def advance(by: 1, failed: 0)
        @done += by
        @failed += failed
        @run_log.advance(@run_id, done: @done, failed: @failed)
      end

      # @param name [String] the item now in progress
      def item(name) = @run_log.advance(@run_id, current_item: name.to_s)

      # @param status [String] "finished", "failed" or "interrupted"
      def finish(status: "finished")
        @heartbeat&.kill
        @heartbeat = nil
        @run_log.finish(@run_id, status:) if @started
      end

      private def start_heartbeat
        return unless @heartbeat_every

        # rubocop:disable ThreadSafety/NewThread -- the heartbeat must keep writing while the main
        # thread is blocked in a long Pass 2 call; the thread only touches @run_log and is killed
        # by #finish.
        @heartbeat = Thread.new do
          loop do
            sleep @heartbeat_every
            @run_log.heartbeat(@run_id)
          end
        end
        # rubocop:enable ThreadSafety/NewThread
      end
    end
  end
end
