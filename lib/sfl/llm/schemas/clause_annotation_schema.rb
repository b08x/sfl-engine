# frozen_string_literal: true

require "ruby_llm/schema"

module SFL
  module LLM
    module Schemas
      # Structured-output contract for single-clause Pass 2 annotation —
      # replaces DSPy::Signature's SFLSignature output block (track
      # decision 7). Enum values are sourced from
      # SFL::Core::ClassificationRegistry so the schema and the
      # fuzzy-normalization dimension it feeds can never drift apart.
      #
      # Numeric ranges (modality_weight, tenor) are declared as hard
      # schema constraints rather than guessed-at post hoc: this is the
      # "contract rejection over clamp01 scale-guessing" fix (F6/D9) — an
      # out-of-range value is a contract violation the engine rejects and
      # degrades from, not a value to silently rescale.
      class ClauseAnnotationSchema < RubyLLM::Schema
        string :mood, enum: Core::ClassificationRegistry.canonical_values(:mood)
        number :modality_weight, description: "Certainty 0.0-1.0 (0=weak/hedged, 1=strong/certain)",
          minimum: 0.0, maximum: 1.0
        number :tenor, description: "Formality 0.0-1.0 (0=informal, 1=formal)", minimum: 0.0, maximum: 1.0
        string :speaker_attitude,
          description: "Speaker attitude, e.g. neutral, positive, negative, skeptical, assertive"
        string :topical_theme, description: "Main starting point (Subject, fronted element, or Predicator)"
        string :textual_theme, required: false,
          description: "Conjunctions/connectives at start (e.g. however, therefore, and)"
        string :interpersonal_theme, required: false,
          description: "Modal adjuncts/discourse markers at start (e.g. surely, perhaps, well)"
        string :rheme, required: false, description: "Everything after the Theme"
        string :theme_type, required: false, enum: Core::ClassificationRegistry.canonical_values(:theme_type)
        string :reasoning, description: "Step-by-step reasoning for the classification"
        array :premises, description: "Specific tokens/POS/deps/etc. that support this annotation" do
          object do
            string :type
            string :source
            string :value
            number :weight, required: false
          end
        end
        string :inference_rule,
          description: "Named SFL rule mapping premises to the conclusion, e.g. 'tenor_high_formal_register'"
        number :confidence, description: "Confidence in this annotation, 0.0-1.0", minimum: 0.0, maximum: 1.0
      end
    end
  end
end
