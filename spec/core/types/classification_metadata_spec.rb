# frozen_string_literal: true

require "spec_helper"

RSpec.describe "unknown classification metadata" do
  let(:clause) do
    SFL::Core::Types::SyntacticClause.new(
      id: "c-unknown", text: "Unknown.", tokens: [], root_index: 0,
      sentence_index: 0, document_id: "doc-1"
    )
  end
  let(:ideational) do
    SFL::Core::Types::IdeationalPayload.new(
      clause_id: "c-unknown", process_type: "material", participants: [],
      circumstances: [], raw_transitivity: {}
    )
  end

  it "preserves the raw value and marks an unknown mood untrusted" do
    annotator = instance_double(SFL::LLM::Annotators::ClauseAnnotator,
      call: {mood: "novel_mood", modality_weight: 0.5, tenor: 0.5, theme_type: "unmarked"})
    engine = SFL::LLM::Engine.new(clause_annotator: annotator, batch_clause_annotator: double)

    result = engine.annotate(clause, ideational)

    expect(result.interpersonal).to have_attributes(
      mood: "declarative", raw_classification: "novel_mood",
      classification_status: "unknown", untrusted: true
    )
    expect(SFL::Core::Wire.dump(result.interpersonal)).to include(
      raw_classification: "novel_mood", classification_status: "unknown", untrusted: true
    )
  end
end
