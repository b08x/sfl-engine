# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe SFL::Formatters::KBReportWriter do
  let(:artifact) { build_knowledge_artifact(artifact_id: 1, title: "Introduction") }
  let(:manifest_entry) { build_migration_manifest_entry(artifact_id: 1, title: "Introduction") }
  let(:report) do
    build_knowledge_base_report(
      metadata: { artifact_count: 1, file_count: 1 }, artifacts: [artifact], migration_manifest: [manifest_entry]
    )
  end

  it "writes the CSV/JSON/Markdown trio under output_dir and returns their paths" do
    Dir.mktmpdir do |dir|
      output_dir = File.join(dir, "kb_reports")

      paths = described_class.write(report, output_dir)

      expect(paths.keys).to contain_exactly(:csv, :json, :markdown)
      expect(File).to exist(paths[:csv])
      expect(File).to exist(paths[:json])
      expect(File).to exist(paths[:markdown])
      expect(paths[:json]).to eq(File.join(output_dir, "kb_migration.json"))
    end
  end

  it "creates output_dir if it does not already exist" do
    Dir.mktmpdir do |dir|
      output_dir = File.join(dir, "nested", "kb_reports")

      expect { described_class.write(report, output_dir) }.not_to raise_error
      expect(Dir).to exist(output_dir)
    end
  end
end
