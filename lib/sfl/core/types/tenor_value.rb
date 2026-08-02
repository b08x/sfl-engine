# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Coercible, not strict Float — see ModalityWeight's comment for why
      # (same LLM-boundary-integer failure mode, live-verified 2026-08-02).
      TenorValue = Types::Coercible::Float.constrained(gteq: 0.0, lteq: 1.0)
    end
  end
end
