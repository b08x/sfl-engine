# frozen_string_literal: true

require "sequel"

module SFL
  module Store
    # Postgres-backed store for the annotation-review flow: whether an
    # already-stored, already-trusted-as-text Pass 2 annotation (mood,
    # tenor, ...) needs human confirmation. Ported from legacy's
    # ClauseRepository#record_review/#reviews_for/#review_queue — kept as
    # its own class here (not folded into PgClauseStore) because it has a
    # different lifecycle (append-only audit trail, no delete/replace) and
    # a different consumer (the HITL review queue, not the compile
    # pipeline).
    #
    # NOT a Core::Ports adapter (no port/Null double defined for this) —
    # see the slice report: unlike ClauseStore/EmbeddingStore/Retriever,
    # nothing in this codebase yet needs a swappable backend for the
    # review flow, and the pipeline never touches it. Adding a duck-type
    # contract with no second implementation and no current caller would
    # be speculative generality, not the established ports-and-adapters
    # pattern paying for itself.
    class PgAnnotationReviewRepository
      # Clause listing columns the review queue needs to render: the base
      # clause row plus enough of both payloads to show why a clause needs
      # attention (mood/tenor/process_type) and the evidence for it
      # (reasoning/reasoning_trace) — mirrors legacy's
      # ClauseRepository::REVIEW_QUEUE_COLUMNS, minus the topic_id/
      # topic_label columns that don't exist in v2's clauses table (see
      # db/migrations/001_create_clauses.rb).
      REVIEW_QUEUE_COLUMNS = [
        Sequel[:clauses][:external_id].as(:id),
        Sequel[:clauses][:text],
        Sequel[:clauses][:document_id],
        Sequel[:clauses][:source_type],
        Sequel[:ideational_payloads][:process_type],
        Sequel[:ideational_payloads][:participants],
        Sequel[:ideational_payloads][:circumstances],
        Sequel[:interpersonal_payloads][:mood],
        Sequel[:interpersonal_payloads][:modality_weight],
        Sequel[:interpersonal_payloads][:tenor],
        Sequel[:interpersonal_payloads][:speaker_attitude],
        Sequel[:interpersonal_payloads][:annotation_source],
        Sequel[:interpersonal_payloads][:reasoning],
        Sequel[:interpersonal_payloads][:reasoning_trace],
      ].freeze

      # @param db [Sequel::Database]
      def initialize(db)
        @db = db
      end

      # Persist a human review decision as an audit-trail row. Does not
      # mutate interpersonal_payloads itself — flipping annotation_source
      # to "human" happens where new interpersonal values actually get
      # written (a re-annotation path, out of scope here), not here. This
      # method's only job is to make the decision durable and
      # attributable — same division of responsibility as legacy's
      # ClauseRepository#record_review.
      #
      # @param clause_id [String]
      # @param decision [String] one of Core::Types::ReviewDecision
      # @param original_annotation_source [String] the clause's
      #   annotation_source at the moment of decision, snapshotted so the
      #   audit trail survives later re-annotation overwriting it
      # @param reviewer [String, nil]
      # @param notes [String, nil]
      # @return [Core::Types::AnnotationReview]
      def record_review(clause_id:, decision:, original_annotation_source:, reviewer: nil, notes: nil)
        review = Core::Types::AnnotationReview.new(
          clause_id:, decision:, original_annotation_source:, reviewer:, notes:
        )
        @db[:annotation_reviews].insert(review_row(review))
        review
      end

      # @param clause_id [String]
      # @return [Array<Hash>] review rows for a clause, oldest first — plain
      #   Hashes, not typed structs: this is a historical listing/browse
      #   method (same as PgClauseStore#find_by_document's sibling
      #   listing-style callers elsewhere in this app), not a value crossing
      #   a use-case boundary the way the just-recorded review above is.
      def reviews_for(clause_id)
        @db[:annotation_reviews].where(clause_id:).order(:reviewed_at).all
      end

      # The HITL review queue: clauses whose annotation_source isn't
      # trusted (Core::Types::TRUSTED_ANNOTATION_SOURCES), excluding
      # clauses a human has already accepted as-is. Live-verified bug this
      # exclusion fixes (ported from legacy's own comment, not
      # hypothetical): "Accept" deliberately leaves annotation_source
      # untouched (see #record_review), so without excluding already-
      # accepted clauses here, "Accept" would never actually clear an item
      # from the queue — a human would have to re-decide the same clause
      # every time the queue reloads. "rejected" does NOT exclude — an
      # unresolved disagreement should keep showing up.
      #
      # @param limit [Integer]
      # @param offset [Integer]
      # @return [Hash] { clauses: Array<Hash>, total: Integer }
      def review_queue(limit: 50, offset: 0)
        scope = needs_attention_scope
          .exclude(Sequel[:clauses][:external_id] => accepted_clause_ids)

        total = scope.count
        rows = scope
          .order(Sequel[:clauses][:created_at])
          .limit(limit, offset)
          .select(*REVIEW_QUEUE_COLUMNS)
          .all

        { clauses: rows, total: }
      end

      private def review_row(review)
        {
          id: review.id,
          clause_id: review.clause_id,
          decision: review.decision,
          original_annotation_source: review.original_annotation_source,
          reviewer: review.reviewer,
          notes: review.notes,
          reviewed_at: review.reviewed_at,
          created_at: Time.now,
        }
      end

      # Joins clauses to both payload tables the same explicitly-qualified
      # way PgHybridRetriever's #joined_from_clauses does (Sequel[:clauses]
      # [:external_id] resolves the otherwise-ambiguous clause_id/
      # external_id join key once two payload tables share the FROM
      # clause) — not pulled into ClauseFilters, since that module's
      # #apply expects a RetrievalFilters struct, not the fixed
      # trusted-source/accepted-ids predicate this queue applies.
      private def needs_attention_scope
        @db[:clauses]
          .join(:ideational_payloads, clause_id: Sequel[:clauses][:external_id])
          .join(:interpersonal_payloads, clause_id: Sequel[:clauses][:external_id])
          .exclude(Sequel[:interpersonal_payloads][:annotation_source] => Core::Types::TRUSTED_ANNOTATION_SOURCES)
      end

      private def accepted_clause_ids
        @db[:annotation_reviews].where(decision: "accepted").select(:clause_id)
      end
    end
  end
end
