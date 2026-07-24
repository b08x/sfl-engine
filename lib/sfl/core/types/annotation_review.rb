# frozen_string_literal: true

module SFL
  module Core
    module Types
      # An audit-trail row for a human review decision on a clause —
      # deliberately separate from the clause's own interpersonal payload
      # rather than columns on it, so the original machine annotation is
      # never overwritten silently: this row preserves what
      # annotation_source the clause carried *before* the decision,
      # alongside who decided what and why. Multiple reviews per clause are
      # possible (e.g. reject, re-annotate, accept).
      class AnnotationReview < Dry::Struct
        attribute(:id, Types::String.default { SecureRandom.uuid })
        attribute :clause_id, Types::String
        attribute :decision, ReviewDecision
        attribute :original_annotation_source, AnnotationSource
        attribute :reviewer, Types::String.optional.default(nil)
        attribute :notes, Types::String.optional.default(nil)
        attribute(:reviewed_at, Types::Time.default { Time.now })
      end
    end
  end
end
