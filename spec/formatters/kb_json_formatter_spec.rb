# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe SFL::Formatters::KBJsonFormatter do
  subject(:parsed) { JSON.parse(described_class.new(report).render, symbolize_names: true) }

  let(:artifact) { build_knowledge_artifact(artifact_id: 1, title: "Introduction", last_updated: Time.new(2024, 1, 1)) }
  let(:manifest_entry) { build_migration_manifest_entry(artifact_id: 1, title: "Introduction") }
  let(:report) do
    build_knowledge_base_report(
      metadata: { artifact_count: 1, file_count: 1 }, artifacts: [artifact], migration_manifest: [manifest_entry],
      content_type_distribution: { technical_reference: 1 }, quality_distribution: { high: 1 }
    )
  end

  it "renders metadata and the distribution hashes verbatim" do
    expect(parsed[:metadata]).to eq(artifact_count: 1, file_count: 1)
    expect(parsed[:content_type_distribution]).to eq(technical_reference: 1)
    expect(parsed[:quality_distribution]).to eq(high: 1)
  end

  it "renders migration_manifest entries with action/reason keys" do
    entry = parsed[:migration_manifest].first

    expect(entry).to include(artifact_id: 1, title: "Introduction", action: "keep")
  end

  it "renders artifacts with iso8601 last_updated and all quality/annotation fields" do
    row = parsed[:artifacts].first

    expect(row[:artifact_id]).to eq(1)
    expect(row[:last_updated]).to eq(Time.new(2024, 1, 1).iso8601)
    expect(row).to include(:avg_tenor, :avg_modality, :dominant_mood, :process_types, :annotation_coverage)
  end
end
