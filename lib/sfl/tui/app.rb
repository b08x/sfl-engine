# frozen_string_literal: true

require "dry/monads"
require "ratatui_ruby"
require "securerandom"

module SFL
  module TUI
    # Composition root for sfl-tui. Boot runs once, in .build, before the
    # terminal enters raw mode; .run owns the terminal session.
    module App
      extend self

      # Seconds to wait for a key before redrawing.
      POLL_SECONDS = 0.25

      PIPELINE_OPTIONS = { pass1_only: false, store: true, resume: false }.freeze
      NO_LLM = "recompile needs the LLM settings; sfl-tui started without them"

      # Leaves raw mode and the alternate screen while the block runs (the
      # editor needs the real terminal), then re-enters them.
      TERMINAL_SUSPEND = lambda do |&block|
        RatatuiRuby.restore_terminal
        block.call
      ensure
        RatatuiRuby.init_terminal
      end

      # @param boot [SFL::Boot::Result, nil] pre-built boot result (specs pass one)
      # @param logger [Core::Ports::Logger, nil]
      # @param settings [Boot::TerminalSettings, nil]
      # @return [AppContext]
      # @raise [SFL::Boot::Error] when the database is unreachable or its schema
      #   is behind; exe/sfl-tui prints it before any terminal setup
      def build(boot: nil, logger: nil, settings: nil, suspend: TERMINAL_SUSPEND)
        logger ||= Core::Ports::JournaldLogger.new(progname: "sfl.tui")
        settings ||= Boot.terminal_settings
        boot ||= boot_with_fallback(logger)
        AppContext.new(boot:, logger:, services: services(boot, settings, logger, suspend:))
      end

      # @return [Services] the Postgres-backed collaborators
      def services(boot, settings, logger, suspend: TERMINAL_SUSPEND)
        db = boot.db
        source = Store::PgBrowseSource.new(db)
        run_log = Store::PgRunRepository.new(db)
        Services.new(
          source:,
          review_queue: Store::PgReviewQueueRepository.new(db),
          recompiler: recompiler(boot, logger),
          editor: Core::Ports::ShellEditor.new(command: settings.editor, suspend:),
          opener: Core::Ports::XdgOpener.new,
          run_log:,
          retriever: Store::PgHybridRetriever.new(db:, embedder: boot.embedder || Core::Ports::Null::Embedder.new),
          exporter: Export::Exporter.new(source:, run_log:, dir: settings.export_dir, logger:),
          reviewer: settings.reviewer,
          logger:,
          run_id: -> { SecureRandom.uuid },
          **model_services(boot, logger),
          **launch_services(boot, settings, logger)
        )
      end

      # @return [Hash] the run header, the terminal host and the detached-child spawner
      def launch_services(boot, settings, logger)
        terminal_host = Core::Ports::KittyHost.detect(window_id: settings.kitty_window_id, listen_on: settings.kitty_listen_on)
        logger.info("terminal host chosen", host: terminal_host.class.name)
        {
          run_models: boot.llm_config&.header,
          terminal_host:,
          spawner: Launcher::DetachedChild.new(log_dir: settings.ingest_log_dir, cwd: Launcher::ROOT),
        }
      end

      # @return [Hash] the Models tab's store, resolver and refresher
      def model_services(boot, logger, catalogs: Boot.model_catalogs(load_dotenv: false))
        model_store = Store::PgModelRepository.new(boot.db)
        {
          model_store:,
          model_resolver: boot.model_resolver || Boot::TaskModelResolver.new(env: {}, store: model_store),
          model_refresher: LLM::ModelRefresher.new(catalogs:, store: model_store, logger:),
        }
      end

      # @return [#call] (text, section_id:) -> Result; builds the pipeline on first use
      def recompiler(boot, logger)
        pipeline = nil
        lambda do |text, section_id:|
          next Dry::Monads::Failure(NO_LLM) unless boot.llm_config

          pipeline ||= CLI.build_pipeline(boot, PIPELINE_OPTIONS, breaker: Core::Ports::Null::Breaker.new,
            instrumenter: Core::Ports::Null::Instrumenter.new, logger:)
          pipeline.compile(text, section_id:, store: true, embed: true)
        end
      end

      # @param context [AppContext]
      # @param terminal [#run] RatatuiRuby, which restores the terminal on exit
      # @return [void]
      def run(context, terminal: RatatuiRuby)
        context.logger.info("sfl-tui starting")
        terminal.run do |tui|
          EventLoop.new(
            services: context.services,
            draw: -> (state) { tui.draw { |frame| Program.render(state, frame, tui) } },
            next_message: -> { key_message(tui.poll_event(timeout: POLL_SECONDS)) || Messages::Tick.new(Time.now) }
          ).run
        end
        context.logger.info("sfl-tui exited")
      end

      # A poll that brings no key press yields a Messages::Tick instead.
      # @return [Messages::Key, nil] nil for anything but a key press
      def key_message(event)
        event.is_a?(RatatuiRuby::Event::Key) ? Messages::Key.new(KeyName.call(event)) : nil
      end

      # Review and Search work without the LLM settings, so a missing API key
      # downgrades recompile instead of refusing to start. A schema that is
      # behind (Boot::SchemaError) is re-raised without the fallback, so it
      # stops sfl-tui and logs no LLM-settings warning.
      private def boot_with_fallback(logger)
        Boot.call(require_db: true, require_llm: true, require_tracing: false, require_schema: true)
      rescue Boot::SchemaError
        raise
      rescue Boot::Error => e
        logger.warn("sfl-tui starting without LLM settings", error: e.message)
        Boot.call(require_db: true, require_llm: false, require_tracing: false, require_schema: true)
      end
    end
  end
end
