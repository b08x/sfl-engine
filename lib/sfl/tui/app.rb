# frozen_string_literal: true

require "bubbletea"
require "io/console"

module SFL
  module TUI
    # Composition root for the terminal console (docs/tui-implementation-plan.md
    # §3, §5 Phase 1) — the same shape GUI::ReviewQueueApp uses for the desktop
    # app: collaborators are injectable so every one of these methods is
    # exercisable without a database, a display or a terminal, and Boot.call is
    # only reached when they were left out.
    #
    # Boot is called exactly once, here, with require_llm/require_tracing off:
    # Phase 1 renders no live data, and paying for LLM credential validation
    # and an OTel exporter to draw four empty panes would be wasted startup
    # latency. Widen the call in the phase that first needs a synthesizer.
    module App
      extend self

      # @param boot [SFL::Boot::Result, nil] pre-built boot result (specs pass a fake)
      # @param logger [#debug,#info,#warn,#error, nil]
      # @return [AppContext]
      # @raise [SFL::Boot::Error] propagated deliberately — exe/sfl-tui rescues it
      #   and prints plain stderr text BEFORE any raw-mode/alt-screen entry.
      def build(boot: nil, logger: nil)
        resolved_logger = logger || Core::Ports::JournaldLogger.new(progname: "sfl.tui")
        resolved_boot = boot || SFL::Boot.call(require_db: true, require_llm: false, require_tracing: false)
        width, height = terminal_size

        AppContext.new(boot: resolved_boot, logger: resolved_logger, width:, height:)
      end

      # @param context [AppContext]
      # @return [Program] root MVU model, closing over the context
      def program(context) = Program.new(context:)

      # Runs the event loop until the model returns Bubbletea.quit.
      #
      # Bubbletea::Runner.new(...).run, never Bubbletea.run: the latter
      # discards the runner, and Runner#send is the only cross-thread message
      # injection hook there is. Phase 1 injects nothing, but the entry point
      # must not foreclose it. (Runner#send shadows Object#send and its
      # @pending_messages is an unguarded Array — anything that later exposes a
      # send path has to serialise it behind its own Mutex or Queue.)
      #
      # @return [void]
      def run(context)
        context.logger.info("sfl-tui starting #{context.width}x#{context.height}")
        Bubbletea::Runner.new(program(context), alt_screen: true).run
        context.logger.info("sfl-tui exited")
      end

      # Best-effort; IO.console is nil under a pipe and winsize raises on a
      # detached terminal. Both fall through to AppContext's defaults.
      private def terminal_size
        console = IO.console
        return [nil, nil] unless console

        rows, columns = console.winsize
        [columns, rows]
      rescue
        [nil, nil]
      end
    end
  end
end
