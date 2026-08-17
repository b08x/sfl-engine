# frozen_string_literal: true

require "dspy"

module SFL
  module LLM
    module Signatures
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
      class ClauseAnnotationSignature < DSPy::Signature
        description "Analyze the provided linguistic clause and annotate its SFL properties."

        class Premise < T::Struct
          const :type, String
          const :source, String
          const :value, String
          const :weight, T.nilable(Float)
        end

        input do
          const :context, String, description: "Surrounding context of the clause"
          const :clause, String, description: "The single clause to analyze"
        end

        output do
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
          const :premises, T::Array[Premise], description: "Specific tokens/POS/deps/etc. that support this annotation"
          const :inference_rule, T.any(String, Array), description: <<~DESC
            Named SFL rule mapping premises to the conclusion, e.g. 'tenor_high_formal_register'
          DESC
          const :confidence, Float, description: "Confidence in this annotation, 0.0-1.0"
        end
      end
    end
  end
end
