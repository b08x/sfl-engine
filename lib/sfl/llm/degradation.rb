# frozen_string_literal: true

module SFL
  module LLM
    # Default interpersonal/textual payloads substituted when Pass 2
    # can't produce a real annotation — a rejected/malformed LLM
    # response, a Breaker timeout, or any other failure the engine
    # degrades from rather than raising.
    #
    # `annotation_source: "fallback"` is the point: never "llm". A
    # default that claims to be real model output is a lie a downstream
    # quality score or citation would trust — see
    # SFL::Core::Types::TRUSTED_ANNOTATION_SOURCES, which excludes
    # "fallback" for exactly this reason.
    module Degradation
      module_function def default_interpersonal(clause_id, reason: "Pass 2 annotation unavailable — defaults applied")
        Core::Types::InterpersonalPayload.new(
          clause_id:,
          mood: "declarative",
          modality_weight: 0.5,
          tenor: 0.5,
          speaker_attitude: nil,
          reasoning: reason,
          annotation_source: "fallback"
        )
      end

      module_function def default_textual(clause_id)
        Core::Types::TextualPayload.new(
          clause_id:,
          topical_theme: "unknown",
          textual_theme: nil,
          interpersonal_theme: nil,
          rheme: nil,
          theme_type: "unmarked"
        )
      end
    end
  end
end
