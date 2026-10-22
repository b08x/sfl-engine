# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Durable record of runs (ingest, annotate, export, recompile), keyed by
      # SFL_RUN_ID. Writers call #start, #advance and #heartbeat while the run
      # works and #finish at the end. Readers call #list and #stalled; each
      # returned row carries a `state` from Core::RunState.
      module RunLog
        KINDS = %w[ingest annotate export recompile].freeze

        # @param run_id [String]
        # @param kind [String] one of KINDS
        # @param collection [String, nil]
        # @param total [Integer]
        # @param pid [Integer]
        # @param models [Hash, nil] the run header: task => `{provider, model, source}`
        #   for each task the run's models were resolved for (LLM::Config#header)
        # @return [void]
        def start(run_id:, kind:, collection:, total:, pid:, models: nil)
          raise NotImplementedError, "#{self.class} must implement #start"
        end

        # @param run_id [String]
        # @param fields [Hash] any of total:, done:, failed:, current_item:
        # @return [void]
        def advance(run_id, **fields)
          raise NotImplementedError, "#{self.class} must implement #advance"
        end

        # @param run_id [String]
        # @return [void]
        def heartbeat(run_id)
          raise NotImplementedError, "#{self.class} must implement #heartbeat"
        end

        # @param run_id [String]
        # @param status [String] "finished", "failed" or "interrupted"
        # @return [void]
        def finish(run_id, status:)
          raise NotImplementedError, "#{self.class} must implement #finish"
        end

        # @param limit [Integer]
        # @return [Array<Hash>] newest first, each with a `state`
        def list(limit: 50)
          raise NotImplementedError, "#{self.class} must implement #list"
        end

        # @return [Array<Hash>] rows whose state is "stalled" or "dead"
        def stalled
          raise NotImplementedError, "#{self.class} must implement #stalled"
        end
      end
    end
  end
end
