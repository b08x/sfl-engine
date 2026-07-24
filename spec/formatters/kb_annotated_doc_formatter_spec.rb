# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Formatters::KBAnnotatedDocFormatter do
  subject(:markdown) { described_class.new(artifact).render }

  let(:trusted_clause) do
    build_annotated_clause(text: "Ruby is dynamic.", process_type: "relational", mood: "declarative", tenor: 0.6,
      modality: 0.7, annotation_source: "llm")
  end
  let(:untrusted_clause) { build_annotated_clause(text: "Maybe it compiles.", annotation_source: "fallback") }
  let(:artifact) do
    build_knowledge_artifact(
      artifact_id: 1, section_path: "Introduction", content_type: :technical_reference, quality_score: 0.712,
      migration_action: :keep, clauses: [trusted_clause, untrusted_clause]
    )
  end

  it "renders the section heading, content type, quality, and action" do
    expect(markdown).to include("## Introduction")
    expect(markdown).to include("**Content type**: technical_reference | **Quality**: 0.71 | **Action**: keep")
  end

  it "falls back to an 'Artifact <id>' heading when section_path is nil" do
    headless = build_knowledge_artifact(artifact_id: 7, section_path: nil)

    expect(described_class.new(headless).render).to include("## Artifact 7")
  end

  it "tags each clause inline with process type, mood, tenor, and modality" do
    expect(markdown).to include("Ruby is dynamic.")
    expect(markdown).to include("[relational · declarative · tenor=0.6 · modality=0.7]")
  end

  it "marks clauses from untrusted annotation sources with a warning emoji" do
    expect(markdown).to include("⚠️ `[")
    expect(markdown).to include("of 2 clauses carry fallback/stub annotations")
  end

  it "renders a placeholder when the artifact has no clauses" do
    empty_artifact = build_knowledge_artifact(clauses: [])

    expect(described_class.new(empty_artifact).render).to include("_No clauses extracted._")
  end
end
