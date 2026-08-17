# frozen_string_literal: true

require "dspy"

module SFL
  module LLM
    module Signatures
      # Structured-output contract for Ingest::LoaderDrafter: a candidate
      # loader class name, its Ruby source implementing the
      # Core::Loaders::Source#each_unit contract, and a human-readable
      # explanation of the proposed field mapping. The drafted source is
      # never executed by this schema/adapter itself — see
      # Ingest::LoaderDrafter's own safety-boundary comment.
      class LoaderDraftSignature < DSPy::Signature
        description "Draft a Ruby loader class based on a JSON/CSV schema mapping."

        input do
          const :file_sample, String, description: "A sample of the file content to parse."
          const :filename, String, description: "The name of the file."
        end

        output do
          const :class_name, String, description: "PascalCase class name, e.g. GenericJsonlChatSource"
          const :ruby_source, String, description: "Complete Ruby source for a class under " \
                                        "SFL::Core::Loaders implementing #each_unit (yielding SFL::Core::Types::Unit), " \
                                        "matching the Core::Loaders::Source mixin contract"
          const :field_mapping_explanation, String, description: "Plain-language explanation of how " \
                                                      "sample fields map to speaker/text/sent_at, and why " \
                                                      "no existing loader matched"
          const :confidence, Float, description: "Confidence this draft is usable as-is, 0.0-1.0"
        end
      end
    end
  end
end
