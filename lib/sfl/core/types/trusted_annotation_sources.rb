# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Sources whose values are trusted for grounding answers, quality
      # scoring, and "needs attention" predicates — as opposed to
      # fallback/stub/chunk_artifact, which are compiler-substituted
      # defaults. Centralized so every consumer of annotation_source agrees
      # on what counts as reviewed/reliable without duplicating the
      # `!= "llm"` check that predates "human" as a source.
      TRUSTED_ANNOTATION_SOURCES = %w[llm human].freeze
    end
  end
end
