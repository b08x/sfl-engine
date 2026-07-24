# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe SFL::Formatters::KBAnnotatedDocWriter do
  describe ".write" do
    it "writes one file per distinct source_file, grouping same-file artifacts into one document" do
      guide_intro = build_knowledge_artifact(artifact_id: 1, title: "Guide", source_file: "docs/guide.md",
        section_path: "Intro")
      guide_usage = build_knowledge_artifact(artifact_id: 2, title: "Guide", source_file: "docs/guide.md",
        section_path: "Usage")
      other = build_knowledge_artifact(artifact_id: 3, title: "Other", source_file: "docs/other.md",
        section_path: "Overview")
      report = build_knowledge_base_report(artifacts: [guide_intro, guide_usage, other])

      Dir.mktmpdir do |dir|
        paths = described_class.write(report, dir)

        expect(paths.size).to eq(2)
        expect(paths).to all(satisfy { |p| File.exist?(p) })

        guide_path = paths.find { |p| p.include?("guide") }
        content = File.read(guide_path)
        expect(content).to include("# Guide")
        expect(content).to include("**Source**: `docs/guide.md`")
        expect(content).to include("## Intro")
        expect(content).to include("## Usage")
      end
    end

    it "writes under an 'annotated' subdirectory of output_dir" do
      artifact = build_knowledge_artifact(source_file: "docs/guide.md")
      report = build_knowledge_base_report(artifacts: [artifact])

      Dir.mktmpdir do |dir|
        paths = described_class.write(report, dir)

        expect(paths.first).to start_with(File.join(dir, "annotated"))
      end
    end

    it "disambiguates two source files that share a basename with a numeric suffix" do
      a = build_knowledge_artifact(artifact_id: 1, source_file: "docs/a/README.md")
      b = build_knowledge_artifact(artifact_id: 2, source_file: "docs/b/README.md")
      report = build_knowledge_base_report(artifacts: [a, b])

      Dir.mktmpdir do |dir|
        paths = described_class.write(report, dir)

        expect(paths.map { |p| File.basename(p) }).to contain_exactly("readme.md", "readme-2.md")
      end
    end
  end

  describe ".unique_filename_for" do
    it "returns '<slug>.md' the first time a basename is seen" do
      used = Hash.new(0)

      expect(described_class.unique_filename_for("docs/README.md", used)).to eq("readme.md")
    end

    it "returns '<slug>-2.md' the second time the same basename is seen" do
      used = Hash.new(0)
      described_class.unique_filename_for("docs/a/README.md", used)

      expect(described_class.unique_filename_for("docs/b/README.md", used)).to eq("readme-2.md")
    end
  end
end
