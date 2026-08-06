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

      # Every approve/reject/edit this window writes is attributed to this
      # reviewer. Defaulting it (to a system username, or worse to nil) would
      # produce audit rows nobody can trace back to a person, so an unset
      # variable is a hard startup failure rather than a silent fallback.
      class MissingReviewerNameError < SFL::Error; end

      attr_reader :viewmodel, :logger

      # Collaborators are injectable so this class's non-GUI logic is testable
      # without a database, an LLM or a display — the same kwarg-DI shape
      # ReviewQueueViewModel already uses. In production all three are omitted
      # and built here; Boot.call is only reached when something was left out.
      #
      # @param repo [Store::PgReviewQueueRepository, nil]
      # @param pipeline [Core::Pipeline, nil]
      # @param logger [#debug,#info,#warn,#error, nil]
      # @raise [MissingReviewerNameError] if SFL_REVIEWER_NAME is unset or blank
      def initialize(repo: nil, pipeline: nil, logger: nil)
        @logger = logger || Core::Ports::StandardLogger.new(progname: "sfl.gui")
        # Checked before build_collaborators on purpose: booting the DB and the
        # LLM only to then refuse to start wastes seconds and muddies the error.
        reviewer_name = reviewer_name_from_env
        repo, pipeline = build_collaborators(repo, pipeline)

        @viewmodel = ReviewQueueViewModel.new(repo:, pipeline:, reviewer_name:, logger: @logger)
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

      # @raise [MissingReviewerNameError] if unset, empty or whitespace-only
      # @return [String]
      private def reviewer_name_from_env
        name = ENV.fetch("SFL_REVIEWER_NAME", nil)
        return name unless name.nil? || name.strip.empty?

        raise MissingReviewerNameError,
          "SFL_REVIEWER_NAME must be set — every review-queue decision is attributed to this reviewer"
      end

      # Boot.call opens a DB connection and validates LLM credentials, so it is
      # skipped entirely when both collaborators were injected.
      #
      # @return [Array(Object, Object)] the repo and pipeline to hand the viewmodel
      private def build_collaborators(repo, pipeline)
        return [repo, pipeline] if repo && pipeline

        # require_tracing: false unconditionally — LangfuseReachability's
        # reachability prompt expects an interactive tty, which this GUI
        # process doesn't have in the CLI's sense (see the design doc).
        boot_result = Boot.call(require_llm: true, require_tracing: false)
        [
          repo || Store::PgReviewQueueRepository.new(boot_result.db),
          pipeline || build_pipeline(boot_result),
        ]
      end

      private def build_pipeline(boot_result)
        CLI.build_pipeline(
          boot_result, { pass1_only: false, store: true, resume: false },
          breaker: Core::Ports::Null::Breaker.new, instrumenter: Core::Ports::Null::Instrumenter.new, logger:
        )
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
