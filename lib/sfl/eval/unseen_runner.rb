# frozen_string_literal: true

require "fileutils"
require "securerandom"

module SFL
  module Eval
    # Runs one analysis child process for an eval item: forwards a distinct
    # SFL_RUN_ID, counts turns from the progress line, mirrors child output to
    # run.log and logs start/finish through the injected logger.
    class UnseenRunner
      TASK = "run_unseen"

      # @param logger [Core::Ports::Logger]
      # @param process_runner [#call] `(env, args) { |lines| } -> Process::Status`; yields an
      #   Enumerable of the child's merged output lines
      # @param run_id_factory [#call] returns a fresh run id String per item
      # @param out [#puts] terminal output
      # @param clock [#call] monotonic seconds
      def initialize(logger:, process_runner:, run_id_factory: -> { SecureRandom.uuid }, out: $stdout,
        clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      )
        @logger = logger
        @process_runner = process_runner
        @run_id_factory = run_id_factory
        @out = out
        @clock = clock
      end

      # @return [Hash] `{turns:, success:, exit_status:, log_path:}`
      def run_item(number:, input:, out_dir:, command:)
        item = "nd-#{number}"
        run_id = @run_id_factory.call
        log_path = File.join(out_dir, "run.log")
        FileUtils.mkdir_p(out_dir)
        File.write(log_path, "")
        @out.puts "#{item}: Pass 2 on #{File.basename(input)}"
        @logger.info("eval item started", eval_task: TASK, eval_item: item, item_run_id: run_id)

        started = @clock.call
        turns = 0
        status = @process_runner.call({ "SFL_RUN_ID" => run_id }, command) do |lines|
          lines.each do |line|
            File.write(log_path, line, mode: "a")
            turns = relay(item, line, turns)
          end
        end
        finish(item, run_id, turns, @clock.call - started, status, log_path)
      end

      private def relay(item, line, turns)
        if ProgressLine.parse(line)
          turns += 1
          @out.puts "  #{item}: #{turns} turns processed" if (turns % 10).zero?
        elsif line.match?(/WARN|ERROR|fallback/)
          @out.puts "  #{line}"
        end
        turns
      end

      private def finish(item, run_id, turns, duration, status, log_path)
        fields = {
          eval_task: TASK,
          eval_item: item,
          item_run_id: run_id,
          turns:,
          duration_s: duration.round(2),
          exit_status: status.exitstatus,
        }
        if status.success?
          @logger.info("eval item finished", **fields)
        else
          @logger.error("eval item failed", **fields)
        end
        @out.puts "#{item}: finished, #{turns} turns, exit #{status.exitstatus}"
        { turns:, success: status.success?, exit_status: status.exitstatus, log_path: }
      end
    end
  end
end
