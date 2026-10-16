# frozen_string_literal: true

require "dspy"

module SFL
  module LLM
    module Signatures
      # V2: V1 plus explicit grounding rules. The rules restate what the
      # digest-grounding check measures, so the narrator is told what it will be
      # checked against. Field definitions are duplicated from V1 rather than
      # inherited, so each variant reads on its own.
      class NarrativeSignatureV2 < DSPy::Signature
        GROUNDING_RULES = "Grounding rules: cite the turn behind each claim as 'turn N' using the " \
          "turn numbers in the digest. Keep every number exactly as the digest states it, with no " \
          "rounding and no new figures. Where support is thin, such as a single turn or a low-count " \
          "statistic, hedge the claim in the same sentence."

        description "#{NarrativeSignatureV1.description} #{GROUNDING_RULES}"

        input do
          const :digest, String,
            description: "Statistics, speaker profiles, correlations, and " \
              "per-turn stance rows with message previews"
        end

        output do
          const :overview, String, description: "What this conversation is: topic, participants, setting"
          const :cast_and_roles, String, description: "Each speaker's role as the grammar reveals it"
          const :interpersonal_dynamics, String, description: "Tenor/modality patterns and shifts between speakers"
          const :conversational_arc, String, description: "Phases, pivots, and how the interaction resolves"
          const :data_quality, String, description: "Annotation coverage caveats; which turns are unmeasured"
          const :takeaways, String, description: "Three to five grounded conclusions"
        end
      end
    end
  end
end
