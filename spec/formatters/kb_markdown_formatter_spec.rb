# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Formatters::KBMarkdownFormatter do
  subject(:markdown) { described_class.new(report).render }

  let(:artifact) { build_knowledge_artifact(artifact_id: 1, title: "Introduction") }
  let(:manifest_entry) { build_migration_manifest_entry(artifact_id: 1, title: "Introduction") }
  let(:metadata) { { analyzed_at: "2024-01-01", artifact_count: 1, file_count: 1 } }
  let(:report) do
    build_knowledge_base_report(
      metadata:, artifacts: [artifact], migration_manifest: [manifest_entry],
      content_type_distribution: { technical_reference: 1 }, quality_distribution: { high: 1 }
    )
  end

  it "renders the title and artifact/file counts" do
    expect(markdown).to include("# Knowledge Base Migration Report")
    expect(markdown).to include("**Artifacts**: 1 | **Files**: 1")
  end

  it "renders the migration manifest table with the action emoji" do
    expect(markdown).to include("## Migration Manifest")
    expect(markdown).to include("✅ keep")
  end

  it "renders the content type breakdown" do
    expect(markdown).to include("### Technical Reference (1)")
    expect(markdown).to include("Introduction")
  end

  it "renders images_line only when metadata[:images_analyzed] is true" do
    expect(markdown).not_to include("Images analyzed")

    with_images = build_knowledge_base_report(metadata: metadata.merge(images_analyzed: true), artifacts: [artifact],
      migration_manifest: [manifest_entry])

    expect(described_class.new(with_images).render).to include("**Images analyzed**: yes")
  end

  it "renders a data quality warning when clauses carry non-trusted annotation sources" do
    fallback_clause = build_annotated_clause(annotation_source: "fallback")
    flagged_artifact = build_knowledge_artifact(clauses: [fallback_clause])
    flagged = build_knowledge_base_report(metadata:, artifacts: [flagged_artifact],
      migration_manifest: [manifest_entry])

    expect(described_class.new(flagged).render).to include("⚠️ **Data Quality**")
  end

  it "renders a staleness section when staleness_flags is present" do
    flagged = build_knowledge_base_report(
      metadata:, artifacts: [artifact], migration_manifest: [manifest_entry],
      staleness_flags: [{ artifact_id: 1, last_updated: Time.new(2020, 1, 1) }]
    )

    expect(described_class.new(flagged).render).to include("## ⏰ Staleness Flags")
    expect(described_class.new(flagged).render).to include("Introduction")
  end
end
