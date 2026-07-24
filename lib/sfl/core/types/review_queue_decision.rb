# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Decision vocabulary for the content-review queue (Store::
      # PgReviewQueueRepository#decide) — deliberately separate from
      # ReviewDecision ("accepted"/"rejected"/"re_annotated"), which is the
      # UNRELATED annotation-confidence review flow's vocabulary
      # (Store::PgAnnotationReviewRepository#record_review). "approve" means
      # the generated text is correct as-is; "edit" means a human supplied
      # corrected text (the caller is responsible for recompiling and
      # storing it — this enum only names the decision); "reject" discards
      # the generated text entirely.
      ReviewQueueDecision = String.enum("approve", "edit", "reject")
    end
  end
end
