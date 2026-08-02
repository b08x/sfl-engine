# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Structured derivation for an interpersonal annotation: which
      # premises support it, which named SFL rule maps them to the
      # conclusion, and a SHA256 `derivation_hash` over all three —
      # computed by the Pass 2 engine from the actual returned values,
      # never trusted as an LLM output field (an LLM-emitted hash would
      # verify nothing, since the model could emit any string).
      class ReasoningTrace < Dry::Struct
        attribute :premises, Types::Array.of(Premise)
        attribute :inference_rule, Types::String
        attribute :conclusion, Types::Hash
        # Coercible, not strict Float — see ModalityWeight's comment for why
        # (same LLM-boundary-integer failure mode, live-verified 2026-08-02).
        attribute :confidence, Types::Coercible::Float.constrained(gteq: 0.0, lteq: 1.0)
        attribute :derivation_hash, Types::String
        attribute :generated_at, Types::Time
      end
    end
  end
end
