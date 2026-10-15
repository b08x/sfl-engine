# frozen_string_literal: true

# Verbatim copy of sfl-compiler lib/sfl/compiler/analysis/narrative_generator.rb:339-370
# (NarrativeSignature). Kept for spec/llm/signatures/narrative_signature_v1_spec.rb to diff
# the ported NarrativeSignatureV1 against. Do not edit; re-copy from sfl-compiler if it moves.

require "dspy"

module SflCompilerFixture
  class NarrativeSignature < DSPy::Signature
    description "Write an interpretive analytical narrative of a " \
      "conversation analyzed with Systemic Functional Linguistics. " \
      "Ground every claim in the supplied statistics; quote message " \
      "previews where they illustrate a point. NEVER interpret " \
      "tenor/modality values from turns marked UNRELIABLE — " \
      "describe those turns as unmeasured. Use the KEY MOMENTS entries " \
      "as explicit evidence when describing pivots and anomalies in " \
      "the conversational arc. If the digest opens with a LOW " \
      "CONFIDENCE WARNING, state plainly in data_quality (and " \
      "takeaways) that the analysis rests on a small sample and " \
      "findings are provisional. Style exemplar: " \
      "'Robert is the only speaker who uses imperatives — in SFL " \
      "terms, the only one demanding rather than giving. That " \
      "asymmetry is the facilitator role, recovered from grammar " \
      "alone.' Write clear analytical prose, not bullet dumps."

    input do
      const :analysis_digest, String,
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
