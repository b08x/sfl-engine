# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Ingest::DeterministicRules/Core::Ports::Classifier's verdict on one
      # file: which format it looks like, which of the three existing
      # analysis modes (conversation/knowledge_base/documentation) it
      # should dispatch to, and how confident that verdict is. Mirrors the
      # existing ReasoningTrace pattern (lib/sfl/core/types/reasoning_trace.rb)
      # so classification decisions are auditable the same way Pass 2
      # annotation decisions already are — `reasoning` is always present,
      # never optional.
      #
      # format/mode are plain String, not Symbol: matches how
      # InterpersonalPayload#mood/TextualPayload#theme_type are already
      # stored, and avoids the Symbol-at-a-Postgres-boundary footgun
      # PgReviewQueueRepository#enqueue's own doc comment already flags.
      class ClassificationResult < Dry::Struct
        attribute :format, Types::String
        attribute :mode, Types::String.optional
        # Coercible, not strict Float — same LLM-boundary-integer rationale as
        # ReasoningTrace#confidence (lib/sfl/core/types/reasoning_trace.rb:16-18).
        attribute :confidence, Types::Coercible::Float.constrained(gteq: 0.0, lteq: 1.0)
        attribute :reasoning, Types::String
      end
    end
  end
end
