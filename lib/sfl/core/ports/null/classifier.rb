# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # No-op Classifier: always returns the lowest-confidence "unknown"
        # verdict, so a caller that hasn't wired a real Classifier in
        # (e.g. an unrelated spec) always falls through to
        # Ingest::Orchestrator's review/draft path rather than silently
        # dispatching anywhere.
        class Classifier
          include Ports::Classifier

          def classify(_sample, _path)
            Types::ClassificationResult.new(
              format: "unknown", mode: nil, confidence: 0.0,
              reasoning: "Null::Classifier: no real classifier configured"
            )
          end
        end
      end
    end
  end
end
