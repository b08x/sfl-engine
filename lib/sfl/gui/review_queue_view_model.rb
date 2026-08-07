# frozen_string_literal: true

require "dry/monads"

module SFL
  module GUI
    # Model layer for the review queue GUI (lib/sfl/gui/review_queue_app.rb) —
    # the only class in this app that touches Store::PgReviewQueueRepository/
    # Core::Pipeline directly. Every custom control reads/writes this via
    # Glimmer data-binding, never the repo/pipeline themselves.
    #
    # No Glimmer include here on purpose: this class has no view concerns,
    # which is what makes it unit-testable without a display (see
    # spec/gui/review_queue_view_model_spec.rb).
    #
    # Every action method returns a Dry::Monads::Result, matching
    # Core::Pipeline#compile's own return shape — a deliberate, concrete
    # resolution of the design spec's Finding 5 (left open there as "a
    # return value the calling control turns into a dialog," unspecified
    # shape).
    class ReviewQueueViewModel
      include Dry::Monads[:result]

      # Surfaced when #finish_recompile!'s identity check rejects a stale
      # compile — the user switched rows while a compile was in flight.
      SELECTION_CHANGED_MESSAGE = "selection changed during recompile — the edit was not saved, please retry"

      attr_accessor :items, :selected_item, :modality_filter, :edited_text

      # @param repo [Store::PgReviewQueueRepository]
      # @param pipeline [Core::Pipeline]
      # @param reviewer_name [String] read from ENV by the caller (SFL::GUI::ReviewQueueApp),
      #   not by this class — see this plan's Global Constraints.
      # @param logger [#debug,#info,#warn,#error] Core::Ports::Logger-compatible
      def initialize(repo:, pipeline:, reviewer_name:, logger: Core::Ports::Null::Logger.new)
        @repo = repo
        @pipeline = pipeline
        @reviewer_name = reviewer_name
        @logger = logger
        @items = []
        @selected_item = nil
        @modality_filter = "all"
        @edited_text = nil
      end

      # Rescues StandardError, not just Sequel::Error: this runs at startup and
      # again on every tick of the 10s auto-refresh timer, where an escaping
      # exception unwinds into the libui event loop and takes the window down.
      # A DB outage surfaces as more than Sequel::Error alone (connection-pool,
      # socket and DNS failures all have their own classes), so the net is the
      # whole StandardError hierarchy. Spelled as a bare `rescue` to match
      # #compile_edited_text and this project's Style/RescueStandardError.
      #
      # @return [Dry::Monads::Result] Success(items) or Failure(message)
      def refresh!
        self.items = repo.pending(modality: modality_filter_param).fetch(:items)
        sync_selection_after_refresh
        Success(items)
      rescue => e
        logger.warn { "review queue refresh failed: #{e.message}" }
        Failure(e.message)
      end

      # No-ops on nil rather than raising: #items can shrink between a table
      # repaint and a row click (the 10s auto-refresh timer resolving a row out
      # from under the user), so ItemListControl's `items[row]` lookup can hand
      # us nil. Guarding here rather than at the call site protects every caller.
      #
      # Row-index entry point for ItemListControl's on_row_clicked. The control
      # hands over the index it was given and nothing else; which item that
      # index names is this class's business, not the view's (SIFT S-2 —
      # previously the control scripted `viewmodel.select(viewmodel.items[row])`).
      # An index past the end resolves to nil, which #select no-ops on. Negative
      # indices are rejected rather than passed to Array#[], where -1 would
      # quietly select the last row instead of nothing.
      #
      # @param index [Integer, nil] the clicked table row index
      def select_row(index)
        return if index.nil? || index.negative?

        select(items[index])
      end

      # @param item [Hash, nil] a row from #items
      def select(item)
        return if item.nil?

        self.selected_item = item
        self.edited_text = item[:generated_text]
      end

      # Identity used by #finish_recompile! to detect a stale compile — capture
      # this before starting a background compile, then compare it against the
      # live value once the compile finishes.
      #
      # @return [Object, nil] the selected item's id, or nil if nothing selected
      def selected_item_id
        selected_item&.dig(:id)
      end

      # @return [Symbol, nil] :image | :text | :unrecognized | nil (nothing selected)
      def detail_kind
        return nil if selected_item.nil?

        case selected_item[:modality]
        when "image" then :image
        when "text", "audio" then :text
        else :unrecognized
        end
      end

      # @return [Dry::Monads::Result]
      def approve!
        decide!("approve")
      end

      # @return [Dry::Monads::Result]
      def reject!
        decide!("reject")
      end

      # #compile returns a Result for expected failures, but it reaches the
      # network (LLM calls, embedding) and can raise for unexpected ones. An
      # exception escaping here would unwind into the libui event loop and take
      # the whole window down, so it is converted to this method's own Failure
      # contract instead.
      #
      # @return [Dry::Monads::Result]
      def save_and_recompile!
        compiled_item_id = selected_item_id
        finish_recompile!(compile_for_recompile, compiled_item_id:)
      end

      # Phase 1 of #save_and_recompile!, split out so a GUI control can run the
      # slow half off the UI thread (SIFT F-1 follow-up).
      #
      # Mutates nothing. It only reads edited_text/selected_item and calls
      # pipeline.compile, so it is safe to call from a background thread: none
      # of Glimmer's observed writers fire, and therefore no libui C call is
      # made from off the main thread. Everything that *does* mutate observed
      # state lives in #finish_recompile! instead.
      #
      # @return [Dry::Monads::Result] pipeline.compile's own Result
      def compile_for_recompile
        return Failure("no item selected") unless selected_item

        compile_edited_text
      end

      # Phase 2 of #save_and_recompile!: records the decision and refreshes.
      #
      # This is the half that assigns items/selected_item/edited_text, each of
      # which Glimmer observes and synchronously pushes into libui — so a GUI
      # caller MUST invoke this inside Glimmer::LibUI.queue_main, on the main
      # thread. Passing a failed compile Result through short-circuits, exactly
      # as the original inline flow did.
      #
      # The identity check is what makes backgrounding safe. The table stays
      # interactive during a compile, so the user can click a different row
      # while one is in flight; #select_row would move selected_item, and a
      # decide! reading it *now* would record the edit against the wrong queue
      # item. Comparing against the id captured before the compile started
      # blocks that write before it happens — decide! is never reached with a
      # mismatched row, so nothing is misattributed and then corrected.
      #
      # A vanished selection (the 10s timer resolved the row) lands here too:
      # selected_item_id is nil, which fails the comparison.
      #
      # @param compile_result [Dry::Monads::Result] from #compile_for_recompile
      # @param compiled_item_id [Object, nil] #selected_item_id as captured
      #   before the compile began
      # @return [Dry::Monads::Result]
      def finish_recompile!(compile_result, compiled_item_id:)
        return compile_result if compile_result.failure?
        return Failure(SELECTION_CHANGED_MESSAGE) unless selected_item_id == compiled_item_id

        decide!("edit")
      end

      attr_reader :repo, :pipeline, :reviewer_name, :logger
      private :repo, :pipeline, :reviewer_name, :logger

      private def decide!(decision)
        return Failure("no item selected") unless selected_item

        repo.decide(id: selected_item[:id], decision:, reviewer: reviewer_name)
        refresh!
      rescue => e
        logger.warn { "review queue #{decision} failed: #{e.message}" }
        Failure(e.message)
      end

      # A bare `rescue` is StandardError; spelled this way to satisfy this
      # project's Style/RescueStandardError setting.
      #
      # @return [Dry::Monads::Result]
      private def compile_edited_text
        pipeline.compile(edited_text, document_id: selected_item[:document_id], store: true, embed: true)
      rescue => e
        logger.error { "review queue recompile raised: #{e.class}: #{e.message}" }
        Failure(e.message)
      end

      private def modality_filter_param
        (modality_filter == "all") ? nil : modality_filter
      end

      # Preserves selection/edited_text across a refresh IF the selected row is still
      # pending; clears both if it disappeared (resolved by this app or another process).
      private def sync_selection_after_refresh
        return unless selected_item

        still_present = items.find { |item| item[:id] == selected_item[:id] }
        self.selected_item = still_present
        self.edited_text = nil unless still_present
      end
    end
  end
end
