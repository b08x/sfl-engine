# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Coercible, not strict Float: an LLM emitting a boundary value (0 or
      # 1, not 0.0/1.0) as a bare JSON integer must not fail the whole
      # clause's annotation over a type it can't meaningfully distinguish
      # from the float — live-verified failure mode (2026-08-02), same
      # class of bug Premise#type's own comment documents.
      ModalityWeight = Types::Coercible::Float.constrained(gteq: 0.0, lteq: 1.0)
    end
  end
end
