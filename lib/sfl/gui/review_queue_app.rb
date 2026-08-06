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

      attr_reader :viewmodel

      def initialize
        # require_tracing: false unconditionally — LangfuseReachability's
        # reachability prompt expects an interactive tty, which this GUI
        # process doesn't have in the CLI's sense (see the design doc).
        boot_result = Boot.call(require_llm: true, require_tracing: false)
        logger = Core::Ports::StandardLogger.new(progname: "sfl.gui")
        pipeline = CLI.build_pipeline(
          boot_result, { pass1_only: false, store: true, resume: false },
          breaker: Core::Ports::Null::Breaker.new, instrumenter: Core::Ports::Null::Instrumenter.new, logger:
        )
        repo = Store::PgReviewQueueRepository.new(boot_result.db)
        reviewer_name = ENV.fetch("SFL_REVIEWER_NAME", nil)

        @viewmodel = ReviewQueueViewModel.new(repo:, pipeline:, reviewer_name:, logger:)
        @viewmodel.refresh!
      end

      def launch
        Glimmer::LibUI.timer(REFRESH_INTERVAL_SECONDS) { viewmodel.refresh! }

        window("SFL Review Queue", 900, 500) {
          margined true

          horizontal_box {
            item_list_control(viewmodel:)
            detail_pane_control(viewmodel:)
          }
        }.show
      end
    end
  end
end
