# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # Stub Annotator: never calls an LLM, always returns a truthfully-
        # labeled ("stub") default payload. This is what `--pass1-only`
        # should wire in — the honesty of `annotation_source: "stub"` here
        # is the whole point (see track decision 13: the legacy bug was a
        # code path that skipped annotation but didn't skip *this* label).
        class Annotator
          include Ports::Annotator

          def annotate(clause, context: {}) # rubocop:disable Lint/UnusedMethodArgument -- context stays in the signature to match the Annotator port contract
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

          def annotate_batch(clauses, context: {})
            clauses.map { |clause| annotate(clause, context:) }
          end
        end
      end
    end
  end
end
