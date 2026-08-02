# frozen_string_literal: true

require "tty-progressbar"

module SFL
  module CLI
    # Replaces the old progress_starter/progress_printer print/puts pair
    # with one TTY::ProgressBar row plus permanent bar.log() lines for each
    # turn's start and outcome. An ETA is genuinely useful here, not just
    # cosmetic — a single turn's Pass 1 + Pass 2 has been observed taking
    # 30-235s live (real LLM latency), so a run of any size is minutes long.
    #
    # #start/#advance are plain instance methods (not lambdas) passed as
    # Method objects to Analysis::Engine's on_turn_start:/on_progress:
    # (both `#call`-duck-typed per that class's own doc comment) — a class
    # is the natural way to share the lazily-created @bar between the two
    # separately-invoked callbacks.
    class TurnProgressBar
      FORMAT = "[:bar] :current/:total :percent (:eta remaining)"

      # @param event [Hash] {turn_id:, total:, speaker:} — see
      #   Analysis::Engine#report_progress's sibling on_turn_start call
      def start(event)
        @bar ||= TTY::ProgressBar.new(FORMAT, total: event[:total], hide_cursor: true)
        @bar.log("  #{event[:turn_id]}/#{event[:total]} (#{event[:speaker]})...")
      end

      # @param event [Hash] {turn_id:, total:, speaker:, elapsed:, clause_count:, defaulted:, turn:}
      def advance(event)
        status = event[:defaulted].zero? ? "OK" : "#{event[:defaulted]}/#{event[:clause_count]} DEFAULTED"
        @bar.log("    #{event[:elapsed]}s [#{status}]")
        @bar.advance
      end
    end
  end
end
