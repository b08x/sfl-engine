# frozen_string_literal: true

module SFL
  module API
    # Application-level service (issue #2) wrapping the POST /clauses/:id/review
    # write path in one database transaction.
    #
    # Server#review_clause previously called reannotate_clause (a Pass 2
    # re-run + PgClauseStore#update_interpersonal write) and
    # PgAnnotationReviewRepository#record_review as two independent,
    # unwrapped Sequel statements. Each one autocommits on its own — a
    # failure between them (record_review raising after
    # update_interpersonal already committed, or vice versa) could leave the
    # stored interpersonal annotation and its own audit trail permanently
    # inconsistent, with no way to tell from the data alone that the write
    # was interrupted mid-flight.
    #
    # Not a Core::Ports adapter (same rationale PgAnnotationReviewRepository's
    # own comment gives for itself): one Postgres-specific implementation,
    # no second backend, no pipeline caller — a duck-type contract here
    # would be speculative generality.
    class ClauseReviewService
      # @param db [Sequel::Database] the shared connection every collaborator
      #   below issues queries against — Sequel's #transaction wraps whatever
      #   statements run on this same object inside the block, so
      #   clause_store/annotation_review_repo don't need their own
      #   transaction-awareness, only to share this db.
      # @param clause_store [Store::PgClauseStore]
      # @param annotation_review_repo [Store::PgAnnotationReviewRepository]
      # @param pass_two [Core::Ports::Annotator]
      def initialize(db:, clause_store:, annotation_review_repo:, pass_two:)
        @db = db
        @clause_store = clause_store
        @annotation_review_repo = annotation_review_repo
        @pass_two = pass_two
      end

      # @param clause_id [String]
      # @param decision [String] one of Core::Types::ReviewDecision
      # @param reviewer [String, nil]
      # @param notes [String, nil]
      # @return [Core::Types::AnnotationReview, nil] nil when the clause doesn't exist
      def review(clause_id:, decision:, reviewer: nil, notes: nil)
        clause = @clause_store.find(clause_id)
        return nil unless clause

        original_source = clause.interpersonal.annotation_source

        @db.transaction do
          reannotate(clause) if decision == "re_annotated"
          @annotation_review_repo.record_review(
            clause_id:, decision:, original_annotation_source: original_source, reviewer:, notes:
          )
        end
      end

      private def reannotate(clause)
        annotated = @pass_two.annotate(clause.syntactic, clause.ideational)
        @clause_store.update_interpersonal(clause.id, annotated.interpersonal)
      end
    end
  end
end
