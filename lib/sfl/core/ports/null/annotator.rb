# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # Stub Annotator: never calls an LLM, always returns a truthfully-
        # labeled ("stub") default result. This is what `--pass1-only`
        # should wire in — the honesty of `annotation_source: "stub"` here
        # is the whole point (see track decision 13: the legacy bug was a
        # code path that skipped annotation but didn't skip *this* label).
        class Annotator
          include Ports::Annotator

          def annotate(clause, _ideational, context: {}) # rubocop:disable Lint/UnusedMethodArgument -- context stays in the signature to match the Annotator port contract
            Types::AnnotationResult.new(interpersonal: stub_interpersonal(clause), textual: stub_textual(clause))
          end

          def annotate_batch(pairs, context: {})
            pairs.map { |clause, ideational| annotate(clause, ideational, context:) }
          end

          private def stub_interpersonal(clause)
            Types::InterpersonalPayload.new(
              clause_id: clause.id,
              mood: "declarative",
              modality_weight: 0.5,
              tenor: 0.5,
              speaker_attitude: nil,
              reasoning: nil,
              annotation_source: "stub"
            )
          end

          private def stub_textual(clause)
            Types::TextualPayload.new(
              clause_id: clause.id,
              topical_theme: nil,
              textual_theme: nil,
              interpersonal_theme: nil,
              rheme: nil,
              theme_type: nil
            )
          end
        end
      end
    end
  end
end
