# frozen_string_literal: true

require "digest"
require "json"

module SFL
  module LLM
    # Canonical-hashing algorithm for reasoning-trace provenance. Computed
    # by the engine from the actual returned premises/inference_rule/
    # conclusion — never trusted as an LLM output field, since an
    # LLM-emitted hash would verify nothing (the model could emit any
    # string it wants).
    #
    # Accepts premises as either SFL::Core::Types::Premise instances or
    # plain Hashes; keys are stringified before hashing so symbol-keyed
    # and string-keyed input produce identical output.
    module DerivationHash
      module_function def compute(premises:, inference_rule:, conclusion:)
        canonical = JSON.generate(
          premises: normalized_premises(premises),
          inference_rule:,
          conclusion: stringify_keys(conclusion).sort.to_h
        )
        Digest::SHA256.hexdigest(canonical)
      end

      module_function def normalized_premises(premises)
        premises
          .map { |p| stringify_keys(p.respond_to?(:to_h) ? p.to_h : p) }
          .sort_by { |p| [p["type"], p["source"]] }
      end

      module_function def stringify_keys(hash)
        hash.transform_keys(&:to_s)
      end
    end
  end
end
