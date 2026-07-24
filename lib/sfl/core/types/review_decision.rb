# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Outcome of a human review decision on a flagged clause. "accepted"
      # leaves the existing interpersonal values as-is but records that a
      # human signed off on them; "rejected" records disagreement without
      # supplying a replacement; "re_annotated" means the human supplied (or
      # triggered a cache-bypassed Pass 2 recompile producing) new values,
      # which is what actually flips annotation_source to "human" on the
      # clause's own interpersonal payload.
      ReviewDecision = String.enum("accepted", "rejected", "re_annotated")
    end
  end
end
