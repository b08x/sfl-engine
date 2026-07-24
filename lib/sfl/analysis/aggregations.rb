# frozen_string_literal: true

module SFL
  module Analysis
    # Shared aggregation helper, ported verbatim from legacy's
    # SFL::Compiler::Analysis::Aggregations (the card's later "unify
    # Aggregations" bullet — F4 rounding etc — is explicitly out of scope
    # for this slice; this is a faithful port, not yet the unification).
    module Aggregations
      def mean(values)
        return 0.5 if values.empty?

        (values.sum / values.size.to_f).round(3)
      end
    end
  end
end
