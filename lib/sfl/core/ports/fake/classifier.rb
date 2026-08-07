# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Fake
        # Deterministic Classifier for specs that need controllable
        # classification output without a real LLM call — mirrors
        # Fake::Embedder's vectors:/default: shape (results keyed by exact
        # sample text; anything unregistered gets a caller-supplied
        # default, defaulting to the same "unknown" verdict
        # Null::Classifier returns).
        class Classifier
          include Ports::Classifier

          def initialize(results: {}, default: Types::ClassificationResult.new(
            format: "unknown", mode: nil, confidence: 0.0,
            reasoning: "Fake::Classifier: no result registered for this sample"
          )
          )
            @results = results
            @default = default
          end

          def classify(sample, _path)
            @results.fetch(sample, @default)
          end
        end
      end
    end
  end
end
