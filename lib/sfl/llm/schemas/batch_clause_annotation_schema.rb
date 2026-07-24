# frozen_string_literal: true

require "ruby_llm/schema"

module SFL
  module LLM
    module Schemas
      # Structured-output contract for batched Pass 2 annotation —
      # replaces DSPy::Signature's SFLBatchSignature/ClauseAnnotation
      # output (track decision 7). Field-by-field identical to
      # ClauseAnnotationSchema (ruby_llm-schema has no schema-composition
      # mechanism to share the object definition, so it's duplicated
      # here rather than reached for indirectly) plus `index`, carrying
      # each annotation back to the input clause it answers.
      class BatchClauseAnnotationSchema < RubyLLM::Schema
        array :annotations, description: "Exactly one annotation per input clause, with matching index" do
          object do
            integer :index
            string :mood, enum: Core::ClassificationRegistry.canonical_values(:mood)
            number :modality_weight, minimum: 0.0, maximum: 1.0
            number :tenor, minimum: 0.0, maximum: 1.0
            string :speaker_attitude
            string :topical_theme
            string :textual_theme, required: false
            string :interpersonal_theme, required: false
            string :rheme, required: false
            string :theme_type, required: false, enum: Core::ClassificationRegistry.canonical_values(:theme_type)
            string :reasoning
            array :premises do
              object do
                string :type
                string :source
                string :value
                number :weight, required: false
              end
            end
            string :inference_rule
            number :confidence, minimum: 0.0, maximum: 1.0
          end
        end
      end
    end
  end
end
