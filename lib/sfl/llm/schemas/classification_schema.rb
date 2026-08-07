# frozen_string_literal: true

require "ruby_llm/schema"

module SFL
  module LLM
    module Schemas
      # Structured-output contract for Ingest classification — mirrors
      # ClauseAnnotationSchema's shape (enum constraints, a required
      # reasoning field) so the "contract rejection over silent
      # scale-guessing" convention (F6/D9) extends to this new LLM call
      # site too: an out-of-range confidence is a schema violation
      # LLM::Classifier rejects, not a value to silently clamp.
      class ClassificationSchema < RubyLLM::Schema
        string :format, description: "A short lowercase_with_underscores tag for the detected file format, " \
                          "e.g. chatgpt_export, markdown_chat, generic_jsonl_chat, unknown"
        string :mode, required: false,
          enum: %w[conversation knowledge_base documentation],
          description: "Which existing analysis mode this file belongs to, omitted if undeterminable"
        number :confidence, description: "Confidence in this classification, 0.0-1.0", minimum: 0.0, maximum: 1.0
        string :reasoning, description: "Step-by-step reasoning for the format/mode classification"
      end
    end
  end
end
