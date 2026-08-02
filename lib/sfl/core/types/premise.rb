# frozen_string_literal: true

module SFL
  module Core
    module Types
      # One piece of evidence (a token, POS tag, dependency relation, etc.)
      # cited as support for a Pass 2 annotation decision.
      class Premise < Dry::Struct
        # Open taxonomy, not an enum: real LLM output uses a far richer
        # vocabulary of evidence categories (e.g. "discourse_marker",
        # "modal_adjunct", "auxiliary_inversion") than any fixed list can
        # anticipate — a 7-value enum here previously caused the *entire*
        # clause (mood/tenor/modality, not just the premise) to default
        # whenever the model used a category outside the list.
        attribute :type, Types::String
        attribute :source, Types::String
        attribute :value, Types::String
        # Coercible, not strict Float — same LLM-boundary-integer failure
        # mode as ModalityWeight/TenorValue (live-verified 2026-08-02): a
        # bare JSON `1` here previously nuked the whole clause's annotation,
        # same class of bug #type's own comment above already documents.
        attribute :weight, Types::Coercible::Float.optional
      end
    end
  end
end
