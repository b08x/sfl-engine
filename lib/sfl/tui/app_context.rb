# frozen_string_literal: true

module SFL
  module TUI
    # Everything the root Program and every workspace sub-model needs, in one
    # immutable bundle. The root model CLOSES OVER this rather than receiving
    # it as an argument (bubbletea-ruby's Model contract is init/0, update/1,
    # view/0 — no context parameter anywhere), and hands it down explicitly to
    # each workspace, whose own contract is init/1, update/2, view/1.
    #
    # - `boot`: the SFL::Boot::Result built once by App.build. Under
    #   Boot.call(require_db: true, require_llm: false, require_tracing: false)
    #   exactly six fields are populated (db, pass1_command, pass1_env,
    #   spacy_model, api_debug_errors, api_cors_origins); llm_config,
    #   lm_factory, embedder and classifier are nil, so no pane may assume
    #   an LLM collaborator exists until a later phase widens the Boot call.
    # - `logger`: a Core::Ports::Logger. Never a StderrLogger — a background
    #   $stderr.puts lands inside the rendered alt-screen frame and
    #   desynchronises the renderer's cursor arithmetic (verified in the
    #   Phase 0 spike).
    # - `width`/`height`: the terminal size. Defaulted defensively because the
    #   first WindowSizeMessage can legitimately report 0x0 when the runtime's
    #   terminal_size call fails; #with_size refuses any non-positive
    #   dimension rather than propagating a zero into the layout arithmetic.
    class AppContext
      DEFAULT_WIDTH = 80
      DEFAULT_HEIGHT = 24

      # Below these the bordered three-pane layout cannot render at all;
      # Layout clamps to them instead of emitting negative widths.
      MIN_WIDTH = 40
      MIN_HEIGHT = 10

      attr_reader :boot, :logger, :width, :height

      def initialize(boot:, logger:, width: DEFAULT_WIDTH, height: DEFAULT_HEIGHT)
        @boot = boot
        @logger = logger
        @width = clamp(width, DEFAULT_WIDTH, MIN_WIDTH)
        @height = clamp(height, DEFAULT_HEIGHT, MIN_HEIGHT)
        freeze
      end

      # @return [AppContext] a copy resized; non-positive dimensions are ignored
      def with_size(width:, height:)
        self.class.new(
          boot:,
          logger:,
          width: positive?(width) ? width : @width,
          height: positive?(height) ? height : @height
        )
      end

      private def clamp(value, fallback, minimum)
        positive?(value) ? [value.to_i, minimum].max : fallback
      end

      private def positive?(value) = value.is_a?(Integer) && value.positive?
    end
  end
end
