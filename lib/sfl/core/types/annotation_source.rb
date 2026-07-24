# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Provenance of interpersonal values: "llm" = real Pass 2 annotation,
      # "fallback" = Pass 2 failed and defaults were substituted, "stub" =
      # Pass 2 was skipped entirely (e.g. --pass1-only runs), "chunk_artifact"
      # = value came from a chunk-boundary default rather than a real
      # annotation, "human" = a reviewer supplied/corrected the values via
      # the HITL review flow — distinct from "llm" because the values didn't
      # come from the compiler, but equally trusted for downstream quality
      # scoring and citation (see TrustedAnnotationSources).
      AnnotationSource = String.default("llm").enum("llm", "fallback", "stub", "chunk_artifact", "human")
    end
  end
end
