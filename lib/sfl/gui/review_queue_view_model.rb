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

      # @return [Dry::Monads::Result] Success(items) or Failure(message)
      def refresh!
        self.items = repo.pending(modality: modality_filter_param).fetch(:items)
        sync_selection_after_refresh
        Success(items)
      rescue Sequel::Error => e
        logger.warn { "review queue refresh failed: #{e.message}" }
        Failure(e.message)
      end

      # @param item [Hash] a row from #items
      def select(item)
        self.selected_item = item
        self.edited_text = item[:generated_text]
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

      # @return [Dry::Monads::Result]
      def save_and_recompile!
        return Failure("no item selected") unless selected_item

        compile_result = pipeline.compile(edited_text, document_id: selected_item[:document_id], store: true,
          embed: true)
        return compile_result if compile_result.failure?

        decide!("edit")
      end

      attr_reader :repo, :pipeline, :reviewer_name, :logger
      private :repo, :pipeline, :reviewer_name, :logger

      private def decide!(decision)
        return Failure("no item selected") unless selected_item

        repo.decide(id: selected_item[:id], decision:, reviewer: reviewer_name)
        refresh!
      rescue Sequel::Error => e
        logger.warn { "review queue #{decision} failed: #{e.message}" }
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
