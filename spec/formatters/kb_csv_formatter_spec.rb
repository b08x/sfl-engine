# frozen_string_literal: true

require "spec_helper"
require "csv"

RSpec.describe SFL::Formatters::KBCsvFormatter do
  subject(:parsed) { CSV.parse(described_class.new(report).render, headers: true) }

  let(:artifact) do
    build_knowledge_artifact(
      artifact_id: 1, title: "Introduction", source_file: "docs/guide.md", section_path: "Intro",
      content_type: :technical_reference, quality_score: 0.712, migration_action: :keep,
      tags: %w[ruby sfl], last_updated: Time.new(2024, 1, 1),
      annotation_coverage: { llm: 3, fallback: 1, stub: 1 }
    )
  end
  let(:report) { build_knowledge_base_report(artifacts: [artifact]) }

  it "emits the expected header row" do
    expect(parsed.headers).to eq(%w[
      artifact_id
      title
      source_file
      section_path
      content_type
      quality_score
      migration_action
      tags
      last_updated
      llm_clause_count
      fallback_clause_count
    ])
  end

  it "emits one row per artifact with rounded quality_score and combined fallback+stub counts" do
    row = parsed.first

    expect(row["artifact_id"]).to eq("1")
    expect(row["title"]).to eq("Introduction")
    expect(row["quality_score"]).to eq("0.712")
    expect(row["tags"]).to eq("ruby; sfl")
    expect(row["last_updated"]).to eq("2024-01-01")
    expect(row["llm_clause_count"]).to eq("3")
    expect(row["fallback_clause_count"]).to eq("2")
  end

  it "defaults clause counts to 0 when annotation_coverage is empty" do
    bare = build_knowledge_artifact(annotation_coverage: {})
    row = CSV.parse(described_class.new(build_knowledge_base_report(artifacts: [bare])).render, headers: true).first

    expect(row["llm_clause_count"]).to eq("0")
    expect(row["fallback_clause_count"]).to eq("0")
  end
end
