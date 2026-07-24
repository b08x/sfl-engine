# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe SFL::Analysis::DocumentationSource do
  describe "#each_unit" do
    it "delegates a single .md file to Core::Loaders::MarkdownSource" do
      units = described_class.new("spec/fixtures/inputs/sample.md").units

      expect(units).not_to be_empty
      expect(units.first.heading).to eq("Introduction")
    end

    it "delegates a single .pdf file to Core::Loaders::PdfSource" do
      units = described_class.new("spec/fixtures/loaders/sample.pdf").units

      expect(units).not_to be_empty
    end

    it "flat-maps units across every .md/.pdf file in a directory" do
      Dir.mktmpdir do |dir|
        FileUtils.cp("spec/fixtures/inputs/sample.md", File.join(dir, "doc.md"))
        FileUtils.cp("spec/fixtures/loaders/sample.pdf", File.join(dir, "doc.pdf"))

        units = described_class.new(dir).units

        md_units = units.select { |u| u.document_id.start_with?("doc.md#", "doc#") }
        expect(units).not_to be_empty
        expect(md_units).not_to be_empty
      end
    end

    it "returns an Enumerator when no block is given" do
      expect(described_class.new("spec/fixtures/inputs/sample.md").each_unit).to be_an(Enumerator)
    end
  end

  describe "#review_entry" do
    it "returns nil when every clause is trusted (llm/human annotation_source)" do
      clauses = [build_annotated_clause(annotation_source: "llm"), build_annotated_clause(annotation_source: "human")]

      expect(described_class.new("x").review_entry(unit: nil, clauses:)).to be_nil
    end

    it "returns a fallback_annotation review Hash when any clause is untrusted" do
      clauses = [
        build_annotated_clause(id: "c1", text: "First.", annotation_source: "llm"),
        build_annotated_clause(id: "c2", text: "Second.", annotation_source: "fallback"),
]

      entry = described_class.new("x").review_entry(unit: nil, clauses:)

      expect(entry).to eq(
        modality: "text", reason: "fallback_annotation", generated_text: "First. Second.",
        source_type: "vault_document"
      )
    end

    it "treats stub and chunk_artifact sources as untrusted too" do
      clauses = [build_annotated_clause(annotation_source: "stub")]

      expect(described_class.new("x").review_entry(unit: nil, clauses:)).not_to be_nil
    end
  end

  describe "#extra_metadata" do
    it "reports section/heading labels and the total clause count across turns" do
      turns = [
        build_turn(clauses: [build_annotated_clause, build_annotated_clause(id: "c2")]),
        build_turn(clauses: [build_annotated_clause(id: "c3")]),
]

      metadata = described_class.new("x").extra_metadata(turns)

      expect(metadata).to include(
        unit_label: "Section", actor_label: "Section", actors_list_label: "Headings", id_label: "document_id",
        clause_count: 3
      )
    end

    it "flags low_confidence true when total clause count is below MIN_CLAUSE_THRESHOLD (30)" do
      turns = [build_turn(clauses: [build_annotated_clause])]

      metadata = described_class.new("x").extra_metadata(turns)

      expect(metadata[:low_confidence]).to be(true)
      expect(metadata[:low_confidence_threshold]).to eq(30)
    end

    it "flags low_confidence false when total clause count meets the threshold" do
      turns = [build_turn(clauses: Array.new(30) { |i| build_annotated_clause(id: "c#{i}") })]

      metadata = described_class.new("x").extra_metadata(turns)

      expect(metadata[:low_confidence]).to be(false)
    end
  end
end
