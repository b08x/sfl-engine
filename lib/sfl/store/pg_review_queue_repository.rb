# frozen_string_literal: true

require "sequel"
require "securerandom"

module SFL
  module Store
    # Postgres-backed content-review queue — separate from
    # PgAnnotationReviewRepository (the Pass 2 annotation-confidence review
    # flow). This tracks whether the underlying TEXT itself (a vision
    # model's description of an image, a low-quality/fallback text
    # extraction, a transcript segment) is trustworthy BEFORE it's
    # permanently stored. Ported from legacy's ReviewQueueRepository.
    #
    # NOT a Core::Ports adapter — see PgAnnotationReviewRepository's class
    # comment for the same reasoning: no current second consumer needs a
    # swappable backend for this admin/HITL flow.
    class PgReviewQueueRepository
      DECISIONS = Core::Types::ReviewQueueDecision.values.freeze

      STATUS_FOR_DECISION = {
        "approve" => "approved",
        "edit" => "edited",
        "reject" => "rejected",
      }.freeze

      # @param db [Sequel::Database]
      def initialize(db)
        @db = db
      end

      # @param document_id [String] stable id; target for a caller's own
      #   clause-store replace on edit/reject
      # @param modality [String] "image" | "text" | "audio"
      # @param source_file [String]
      # @param generated_text [String] the draft under review
      # @param reason [String] e.g. "image" | "fallback_annotation" |
      #   "low_quality_score" | "audio_transcript"
      # @param source_type [String, nil] provenance tag restored on edit's recompile
      # @param content_type [String, nil] — callers may pass a Symbol here;
      #   coerced to String below because Sequel renders a bare Symbol
      #   value as an unquoted SQL identifier rather than a literal,
      #   raising PG::UndefinedColumn (live-verified in legacy, ported
      #   defensively here — every other String-typed param is coerced the
      #   same way as a matching boundary guarantee, not because any v2
      #   caller has been seen passing a Symbol there too).
      # @return [String] the new row's id
      # rubocop:disable Metrics/ParameterLists -- mirrors legacy's #enqueue signature exactly;
      # six independent scalar fields on an insert-only row, no natural grouping to extract.
      def enqueue(document_id:, modality:, source_file:, generated_text:, reason:, source_type: nil, content_type: nil)
        id = SecureRandom.uuid
        @db[:review_queue].insert(
          id:, modality: modality.to_s, document_id: document_id.to_s, source_file: source_file.to_s,
          content_type: content_type&.to_s, source_type: source_type&.to_s,
          generated_text: generated_text.to_s, reason: reason.to_s, status: "pending", created_at: Time.now
        )
        id
      end
      # rubocop:enable Metrics/ParameterLists

      # @param id [String]
      # @return [Hash, nil] the row, nil if not found
      def find(id)
        @db[:review_queue].where(id:).first
      end

      # @param modality [String, nil] filter, nil = all modalities
      # @return [Hash] { items: Array<Hash>, total: Integer }
      def pending(modality: nil, limit: 50, offset: 0)
        scope = @db[:review_queue].where(status: "pending")
        scope = scope.where(modality:) if modality

        total = scope.count
        items = scope.order(:created_at).limit(limit, offset).all
        { items:, total: }
      end

      # @param id [String]
      # @param decision [String] one of DECISIONS
      # @param edited_text [String, nil] not persisted here — the caller is
      #   responsible for recompiling and storing it; this method only
      #   records the decision.
      # @param reviewer [String, nil]
      # @return [Hash, nil] the updated row, nil if id not found
      # rubocop:disable Lint/UnusedMethodArgument -- edited_text is part of this method's public
      # contract (documented above: the caller's job, not this method's, to persist it) and must
      # stay a named keyword so callers/call sites read clearly, even though this method itself
      # never reads it.
      def decide(id:, decision:, edited_text: nil, reviewer: nil)
        raise ArgumentError, "decision must be one of #{DECISIONS.join(', ')}" unless DECISIONS.include?(decision)

        row = @db[:review_queue].where(id:).first
        return nil unless row

        @db[:review_queue].where(id:).update(
          status: STATUS_FOR_DECISION.fetch(decision), reviewer:, reviewed_at: Time.now
        )
        @db[:review_queue].where(id:).first
      end
      # rubocop:enable Lint/UnusedMethodArgument
    end
  end
end
