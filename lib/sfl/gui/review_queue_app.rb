# frozen_string_literal: true

require_relative "review_queue_view_model"
require_relative "item_list_control"
require_relative "detail_pane_control"

module SFL
  module GUI
    # Composition root for the review queue GUI: boots the app's real
    # collaborators (DB, LLM, pipeline) exactly once, builds the
    # ReviewQueueViewModel, and lays out ItemListControl/DetailPaneControl
    # side by side. Owns the auto-refresh timer.
    class ReviewQueueApp
      include Glimmer

      REFRESH_INTERVAL_SECONDS = 10

      attr_reader :viewmodel, :logger

      def initialize
        # require_tracing: false unconditionally — LangfuseReachability's
        # reachability prompt expects an interactive tty, which this GUI
        # process doesn't have in the CLI's sense (see the design doc).
        boot_result = Boot.call(require_llm: true, require_tracing: false)
        @logger = Core::Ports::StandardLogger.new(progname: "sfl.gui")
        pipeline = CLI.build_pipeline(
          boot_result, { pass1_only: false, store: true, resume: false },
          breaker: Core::Ports::Null::Breaker.new, instrumenter: Core::Ports::Null::Instrumenter.new, logger:
        )
        repo = Store::PgReviewQueueRepository.new(boot_result.db)
        reviewer_name = ENV.fetch("SFL_REVIEWER_NAME", nil)

        @viewmodel = ReviewQueueViewModel.new(repo:, pipeline:, reviewer_name:, logger:)
        log_refresh_failure("startup", @viewmodel.refresh!)
      end

      def launch
        Glimmer::LibUI.timer(REFRESH_INTERVAL_SECONDS) { log_refresh_failure("auto-refresh", viewmodel.refresh!) }
        Glimmer::LibUI.queue_main { reapply_visibility_bindings }

        window("SFL Review Queue", 900, 500) {
          margined true

          horizontal_box {
            item_list_control(viewmodel:)
            detail_pane_control(viewmodel:)
          }
        }.show
      end

      # Showing the main window makes GTK show every descendant, which overrides
      # the initial `false` that ImageReviewControl/TextReviewControl's `visible`
      # bindings computed at construction time — so both review panes would be
      # on screen until the first row is clicked. Re-assigning selected_item once
      # the event loop is up re-fires those bindings (they are computed_by it)
      # and restores the intended "nothing selected, nothing shown" state.
      # Writing the value back unchanged is the point: the write is what
      # notifies observers, so the selection itself is deliberately preserved.
      private def reapply_visibility_bindings
        current_selection = viewmodel.selected_item
        viewmodel.selected_item = current_selection
      end

      # A discarded Failure here is the difference between "the queue is empty"
      # and "the database is unreachable", which look identical on screen. The
      # window itself stays as-is (an empty queue is a normal state, not an
      # error dialog), but the reason lands on the terminal the binstub already
      # runs unbuffered.
      #
      # @param phase [String] "startup" or "auto-refresh"
      # @param result [Dry::Monads::Result] the value ReviewQueueViewModel#refresh! returned
      private def log_refresh_failure(phase, result)
        return result unless result.failure?

        logger.warn { "review queue #{phase} refresh failed: #{result.failure}" }
        result
      end
    end
  end
end
