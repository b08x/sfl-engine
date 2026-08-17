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
          const :mood, T.any(String, Array)
          const :modality_weight, Float
          const :tenor, Float
          const :speaker_attitude, T.any(String, Array)
          const :topical_theme, T.any(String, Array)
          const :textual_theme, T.nilable(T.any(String, Array))
          const :interpersonal_theme, T.nilable(T.any(String, Array))
          const :rheme, T.nilable(T.any(String, Array))
          const :theme_type, T.nilable(T.any(String, Array))
          const :reasoning, T.any(String, Array)
          const :premises, T::Array[ClauseAnnotationSignature::Premise]
          const :inference_rule, T.any(String, Array)
          const :confidence, Float
        end

        input do
          const :context, String, description: "Surrounding context of the clauses"
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
