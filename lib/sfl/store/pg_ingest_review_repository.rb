# frozen_string_literal: true

require "sequel"
require "securerandom"

module SFL
  module Store
    # Postgres-backed review queue for Ingest::Orchestrator — rows written
    # when a file can't be confidently classified/dispatched on its own
    # (low-confidence mode, an unrecognized format sent to
    # Ingest::LoaderDrafter, or a failed draft attempt). Mirrors
    # PgReviewQueueRepository's shape deliberately (see
    # db/migrations/009_create_ingest_review_entries.rb's own comment) so
    # a future UI/CLI review subcommand needs no schema change.
    #
    # Not a Core::Ports adapter, same reasoning as PgReviewQueueRepository:
    # no current second consumer needs a swappable backend for this
    # admin/HITL flow.
    class PgIngestReviewRepository
      # @param db [Sequel::Database]
      def initialize(db)
        @db = db
      end

      # @param path [String]
      # @param reasoning [String]
      # @param status [String] "pending" | "low_confidence_mode" |
      #   "loader_drafted" | "draft_failed"
      # @param format [String, nil]
      # @param mode [String, nil]
      # @param confidence [Float, nil]
      # @param loader_path [String, nil] set when status: "loader_drafted"
      # @param doc_path [String, nil] set when status: "loader_drafted"
      # @return [String] the new row's id
      # rubocop:disable Metrics/ParameterLists -- eight independent scalar fields on an
      # insert-only row, same shape as PgReviewQueueRepository#enqueue, no natural grouping.
      def enqueue(path:, reasoning:, status: "pending", format: nil, mode: nil, confidence: nil,
        loader_path: nil, doc_path: nil
      )
        id = SecureRandom.uuid
        @db[:ingest_review_entries].insert(
          id:, path: path.to_s, status: status.to_s, format: format&.to_s, mode: mode&.to_s,
          confidence:, reasoning: reasoning.to_s, loader_path:, doc_path:, created_at: Time.now
        )
        id
      end
      # rubocop:enable Metrics/ParameterLists

      # @param id [String]
      # @return [Hash, nil] the row, nil if not found
      def find(id)
        @db[:ingest_review_entries].where(id:).first
      end

      # @param path [String]
      # @return [Boolean] true if a row for this exact path exists with status "resolved"
      def resolved?(path)
        @db[:ingest_review_entries].where(path: path.to_s, status: "resolved").any?
      end
    end
  end
end
