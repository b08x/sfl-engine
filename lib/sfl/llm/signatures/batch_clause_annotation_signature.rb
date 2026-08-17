# frozen_string_literal: true

require "dspy"
require_relative "clause_annotation_signature"

module SFL
  module LLM
    module Signatures
      # Structured-output contract for batched Pass 2 annotation —
      # replaces DSPy::Signature's SFLBatchSignature/ClauseAnnotation
      # output (track decision 7).
      class BatchClauseAnnotationSignature < DSPy::Signature
        description "Analyze the provided linguistic clauses and annotate their SFL properties."

        class IndexedAnnotation < T::Struct
          const :index, Integer, description: "Matches the input clause index"
          const :mood, T.any(String, Array), description: "Mood classification"
          const :modality_weight, Float, description: "Certainty 0.0-1.0 (0=weak/hedged, 1=strong/certain)"
          const :tenor, Float, description: "Formality 0.0-1.0 (0=informal, 1=formal)"
          const :speaker_attitude, T.any(String, Array), description: <<~DESC
            Speaker attitude, e.g. neutral, positive, negative, skeptical, assertive
          DESC
          const :topical_theme, T.any(String, Array), description: "Main starting point (Subject, fronted element, or Predicator)"
          const :textual_theme, T.nilable(T.any(String, Array)), description: <<~DESC
            Conjunctions/connectives at start (e.g. however, therefore, and)
          DESC
          const :interpersonal_theme, T.nilable(T.any(String, Array)), description: <<~DESC
            Modal adjuncts/discourse markers at start (e.g. surely, perhaps, well)
          DESC
          const :rheme, T.nilable(T.any(String, Array)), description: "Everything after the Theme"
          const :theme_type, T.nilable(T.any(String, Array)), description: "Theme type classification"
          const :reasoning, T.any(String, Array), description: "Step-by-step reasoning for the classification"
          const :premises, T::Array[ClauseAnnotationSignature::Premise], description: "Specific tokens/POS/deps/etc. that support this annotation"
          const :inference_rule, T.any(String, Array), description: <<~DESC
            Named SFL rule mapping premises to the conclusion, e.g. 'tenor_high_formal_register'
          DESC
          const :confidence, Float, description: "Confidence in this annotation, 0.0-1.0"
        end

        input do
          const :clauses, String, description: "Numbered list of clauses to analyze"
        end

        output do
          const :annotations, T::Array[IndexedAnnotation], description: <<~DESC
            Exactly one annotation per input clause, with matching index
          DESC
        end
      end
    end
  end
end
