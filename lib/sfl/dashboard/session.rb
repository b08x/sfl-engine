# frozen_string_literal: true

require "ratatui_ruby"

module SFL
  module Dashboard
    # Owns the terminal while a foreground run works: a terminal thread
    # redraws the Board every POLL_SECONDS and reads keys, while the run
    # executes on the calling thread. $stdout and $stderr are captured into the log for
    # the duration, so nothing writes over the screen.
    #
    # Raw mode delivers Ctrl-C as a key, not SIGINT: the first press sets the
    # stop flag (the run finishes its current item and stops), the second
    # quits at once. When the run returns, the final screen shows the outcome
    # until a key is pressed.
    class Session
      POLL_SECONDS = 0.25

      # Same hard stop as the second Ctrl-C of CLI.install_interrupt_trap.
      ABORT = lambda do
        Signal.trap("INT", "DEFAULT")
        Process.kill("INT", Process.pid)
      end

      attr_reader :board

      # plus the injectable terminal, clock and abort seams; no natural grouping.
      # @param board [Board]
      # @param stop_flag [CLI::StopFlag]
      # @param terminal [#run] RatatuiRuby; yields a TUI and restores the terminal after
      # @param clock [#call] -> Time
      # @param abort [#call] the second Ctrl-C
      # @param hold [Boolean] keep the final screen until a key is pressed
      def initialize(board:, stop_flag:, terminal: RatatuiRuby, clock: -> { Time.now }, abort: ABORT, hold: true)
        @board = board
        @stop_flag = stop_flag
        @terminal = terminal
        @clock = clock
        @abort = abort
        @hold = hold
        @running = false
      end

      # @param level [Integer] minimum severity, Boot::LOG_LEVELS values
      # @return [RingLogger] the log target that replaces stderr
      def logger(level: 1) = RingLogger.new(@board, level:)

      # @param inner [Core::Ports::ProgressSink]
      # @return [Sink] inner, also recorded on the Board
      def sink(inner) = Sink.new(inner:, board: @board)

      # Runs the block on the calling thread with the dashboard drawn.
      # @return [Object] the block's value
      def run(&)
        @running = true
        @keep = false
        # rubocop:disable ThreadSafety/NewThread -- ratatui keeps its terminal in thread-local
        # storage, so one thread must init, draw, poll and restore it; the run itself stays on
        # the calling thread, which blocks in long LLM calls and receives SIGINT. The thread
        # reads the Board under its lock and stops drawing when @running turns false.
        screen = Thread.new { @terminal.run { |tui| show(tui) } }
        # rubocop:enable ThreadSafety/NewThread
        result = capture(&)
        @keep = @hold
        result
      ensure
        @running = false
        screen&.join
      end

      # The terminal thread: redraw until the run returns, then the final
      # screen (kept until a key when the run did not raise).
      private def show(tui)
        draw_loop(tui)
        draw(tui)
        hold(tui) if @keep
      end

      private def draw_loop(tui)
        while @running
          draw(tui)
          key(tui.poll_event(timeout: POLL_SECONDS))
        end
      end

      private def hold(tui)
        loop do
          draw(tui)
          break if tui.poll_event(timeout: POLL_SECONDS).is_a?(RatatuiRuby::Event::Key)
        end
      end

      private def draw(tui)
        state = @board.update { |current| current.tick(@clock.call) }
        tui.draw { |frame| View.render(state, frame, tui) }
      end

      private def key(event)
        return unless ctrl_c?(event)
        return @abort.call if @board.state.stopping

        @stop_flag.stop!
        @board.update(&:stop)
      end

      private def ctrl_c?(event)
        event.is_a?(RatatuiRuby::Event::Key) && event.code.to_s == "c" && event.modifiers.map(&:to_s).include?("ctrl")
      end

      private def capture
        out = $stdout
        err = $stderr
        $stdout = $stderr = OutputCapture.new(@board)
        yield
      ensure
        $stdout = out
        $stderr = err
      end
    end
  end
end
