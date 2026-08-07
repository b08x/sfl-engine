# frozen_string_literal: true

require "ruby_llm/schema"

module SFL
  module LLM
    module Schemas
      # Structured-output contract for Ingest::LoaderDrafter: a candidate
      # loader class name, its Ruby source implementing the
      # Core::Loaders::Source#each_unit contract, and a human-readable
      # explanation of the proposed field mapping. The drafted source is
      # never executed by this schema/adapter itself — see
      # Ingest::LoaderDrafter's own safety-boundary comment.
      class LoaderDraftSchema < RubyLLM::Schema
        string :class_name, description: "PascalCase class name, e.g. GenericJsonlChatSource"
        string :ruby_source, description: "Complete Ruby source for a class under " \
                               "SFL::Core::Loaders implementing #each_unit (yielding SFL::Core::Types::Unit), " \
                               "matching the Core::Loaders::Source mixin contract"
        string :field_mapping_explanation, description: "Plain-language explanation of how " \
                                             "sample fields map to speaker/text/sent_at, and why " \
                                             "no existing loader matched"
        number :confidence, description: "Confidence this draft is usable as-is, 0.0-1.0",
          minimum: 0.0, maximum: 1.0
      end
    end
  end
end
