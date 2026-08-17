# frozen_string_literal: true

require "dspy"

module SFL
  module LLM
    module Signatures
      # Structured-output contract for evidence-grounded query synthesis —
      # replaces DSPy::Signature's SynthesisSignature output block (track
      # decision 7), the same way ClauseAnnotationSignature replaces
      # SFLSignature for Pass 2.
      class SynthesisSignature < DSPy::Signature
        description "Synthesize an answer grounded in the provided linguistic evidence."

        input do
          const :query, String, description: "The user's analytical query"
          const :evidence, String, description: "Numbered list of relevant clauses and annotations"
        end

        output do
          const :answer, String, description: "Answer grounded in the evidence"
          const :cited_clause_numbers, T::Array[Integer], description: <<~DESC
            Evidence numbers actually used (subset of the input numbering)
          DESC
          const :confidence, Float, description: "0.0-1.0, lower when evidence is thin or conflicting"
        end
      end
    end
  end
end
