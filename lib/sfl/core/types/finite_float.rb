# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Shared finite-float guard for this namespace's constrained float
      # types (avg_tenor/avg_modality, quality/confidence scores, tenor
      # values, etc.).
      #
      # Why it exists: dry-logic's gteq/lteq are complement-of-strict
      # comparisons (!(input < n) / !(input > n)), so NaN — which compares
      # false against everything — satisfies both bounds and
      # Types::Float.constrained(gteq: 0.0, lteq: 1.0) accepts it
      # (live-verified on dry-types 1.9.1). +Infinity likewise passes any
      # lone gteq bound. The same applies before coercion on the Coercible
      # base, so ModalityWeight/TenorValue/ReasoningTrace#confidence/
      # ClassificationResult#confidence are exposed the same way.
      #
      # This is defense-in-depth, not a data-shape change: JSON.parse can
      # never produce NaN/Infinity and JSON.generate raises on both, so no
      # persisted cache entry, wire payload, or DB row can contain one —
      # rejecting them cannot break a legacy value. Analysis::ReadabilityScorer
      # already maps non-finite scores to nil (Types::Readability's "not
      # computable" value, which stays valid — its attributes are plain
      # Float.optional and untouched by this guard), so the guard's only job
      # is to trap a future scorer/aggregator regression before it reaches
      # JSON.generate. Both NaN and +/-Infinity are rejected everywhere this
      # guard is composed in: neither is persistable, and +Infinity passing a
      # gteq-only bound (e.g. SpeakerProfile#tenor_variance) is exactly the
      # scorer-bug shape the guard exists to catch.
      module FiniteFloat
        # A range-constrained float type (same bounds semantics as
        # base.constrained(**bounds)) that additionally rejects NaN and
        # +/-Infinity with Dry::Types::ConstraintError.
        #
        # @param base [Dry::Types::Type] Types::Float or
        #   Types::Coercible::Float
        # @param bounds [Hash] dry-logic bounds (gteq:, lteq:, gt:, lt:)
        # @return [Dry::Types::Constrained]
        # @example
        #   FiniteFloat.constrained(Types::Float, gteq: 0.0, lteq: 1.0)
        module_function def constrained(base, **bounds)
          bounded = base.constrained(**bounds)
          bounded.with(rule: bounded.rule & FINITE_RULE)
        end

        # An unbounded finite float type — for float elements inside
        # collection types whose own constraint is not a float range (e.g.
        # SpeakerProfile#tenor_range's size-2 Array), where adding range
        # bounds would tighten semantics beyond the guard.
        #
        # The finite rule is composed AFTER the base's own type rule, not
        # wrapped around the base: Dry::Types::Constrained#call applies its
        # rule to the RAW input before the wrapped type runs, so a
        # Constrained.new(base, rule: FINITE_RULE) would call finite? on a
        # String/nil and raise NoMethodError. Conjuncting into the base
        # (strict Float — a Constrained whose rule is type?(Float), per
        # Dry.Types()'s strict default) lets dry-logic's left-associative
        # And evaluate the type check first, so non-Float input fails with
        # the same typed ConstraintError a plain Float type gives, and
        # FINITE_RULE only ever sees actual Floats (NaN/±Infinity).
        #
        # @param base [Dry::Types::Constrained] Types::Float
        # @return [Dry::Types::Constrained]
        # @example
        #   Types::Array.of(FiniteFloat.value(Types::Float))
        module_function def value(base)
          base.with(rule: base.rule & FINITE_RULE)
        end

        # @api private
        module_function def finite?(value)
          value.finite?
        end

        # A unary dry-logic rule built from this module's own finite?
        # method (the same Method-object shape Dry::Logic::Predicates'
        # entries use), so ConstraintError messages read "finite?(x) failed".
        FINITE_RULE = ::Dry::Logic::Rule::Predicate.build(method(:finite?)).freeze
        private_constant :FINITE_RULE
      end
    end
  end
end
