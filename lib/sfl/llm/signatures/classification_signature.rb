# frozen_string_literal: true

require "dspy"

module SFL
  module LLM
    module Signatures
      # Structured-output contract for Ingest classification — mirrors
      # ClauseAnnotationSignature's shape (enum constraints, a required
      # reasoning field) so the "contract rejection over silent
      # scale-guessing" convention (F6/D9) extends to this new LLM call
      # site too: an out-of-range confidence is a schema violation
      # LLM::Classifier rejects, not a value to silently clamp.
      class ClassificationSignature < DSPy::Signature
        description <<~DESC
          Classify this file sample for an ingest pipeline that routes files to one of three analysis
          modes: "conversation" (chat/dialogue transcripts), "knowledge_base" (reference documents,
          notes, articles), or "documentation" (technical docs, specs, READMEs).
          
          Report a short format tag (e.g. chatgpt_export, markdown_chat, generic_jsonl_chat, unknown),
          which mode this belongs to (omit if you cannot tell), your confidence 0.0-1.0, and your
          reasoning. If the content doesn't look like any recognizable file format at all, use format
          "unknown" and omit mode.
        DESC

        class Mode < T::Enum
          enums do
            Conversation = new("conversation")
            KnowledgeBase = new("knowledge_base")
            Documentation = new("documentation")
          end
        end

        input do
          const :path, String, description: "The file's original path"
          const :sample, String, description: "Sample content to analyze"
        end

        output do
          const :format, String, description: <<~DESC
            A short lowercase_with_underscores tag for the detected file format, e.g. chatgpt_export,
            markdown_chat, generic_jsonl_chat, unknown
          DESC
          const :mode, T.nilable(Mode), description: <<~DESC
            Which existing analysis mode this file belongs to, omitted if undeterminable
          DESC
          const :confidence, Float, description: "Confidence in this classification, 0.0-1.0"
          const :reasoning, String, description: "Step-by-step reasoning for the format/mode classification"
        end
      end
    end
  end
end
