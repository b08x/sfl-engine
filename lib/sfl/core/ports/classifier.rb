# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Ingest-time classification port: given a text sample from a file
      # (not necessarily the whole file — see Ingest::Orchestrator's own
      # sample-size decision), decides which format it looks like and
      # which of the three existing analysis modes it should dispatch to.
      # Only called when Ingest::DeterministicRules finds no match — this
      # port exists for the ambiguous/new-format tail, not the common
      # case (see that module's own comment).
      module Classifier
        # @param sample [String]
        # @param path [String] the file's original path — real adapters may use the
        #   filename/extension as a classification signal (see Ingest::LoaderDrafter#draft's
        #   matching two-arg shape)
        # @return [SFL::Core::Types::ClassificationResult]
        def classify(sample, path)
          raise NotImplementedError, "#{self.class} must implement #classify"
        end
      end
    end
  end
end
