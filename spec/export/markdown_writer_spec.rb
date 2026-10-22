# frozen_string_literal: true

require_relative "export_helper"

# Fact 43: a heading per document, nested headings, a speaker line per turn, clause text.
RSpec.describe SFL::Export::MarkdownWriter do
  it "writes document headings, nested section headings and speaker lines, matching the golden file" do
    output = ExportSpecSupport.write(described_class, ExportSpecSupport.records)

    expect(output).to eq(ExportSpecSupport.golden("papers.md"))
    expect(output).to include("# Paper\n", "## Intro\n", "### Background\n", "# talk.srt\n", "**Alice:**\n")
  end

  it "writes no heading for an unlabelled section" do
    state = TUISpecSupport.browse_state
    picks = state.with(selection: state.selection.select(state.tree, "c:2")).picks
    records = [SFL::Export::ClauseRecord.new(pick: picks.first, id: "n1", text: "A note.", ideational: {}, interpersonal: {})]

    expect(ExportSpecSupport.write(described_class, records)).to eq("# Note\n\nA note.\n\n")
  end

  def pick(**changes)
    SFL::Export::SectionPick.new(collection: "c", document_key: "a.md", title: nil, source_path: "/a.md", section_id: "s",
      kind: "heading", label: "Part", path: ["Part"], depth: 0, order: [0, 1], clause_ids: nil).with(**changes)
  end

  def record(pick, text) = SFL::Export::ClauseRecord.new(pick:, id: text, text:, ideational: {}, interpersonal: {})

  it "repeats a section heading when the same section id starts a new document" do
    records = [record(pick, "One."), record(pick(document_key: "b.md"), "Two.")]

    expect(ExportSpecSupport.write(described_class, records)).to eq("# a.md\n\n## Part\n\nOne.\n\n# b.md\n\n## Part\n\nTwo.\n\n")
  end

  it "caps heading depth at the sixth level" do
    output = ExportSpecSupport.write(described_class, [record(pick(depth: 3), "Deep."), record(pick(depth: 7, section_id: "t"), "Deeper.")])

    expect(output).to eq("# a.md\n\n##### Part\n\nDeep.\n\n###### Part\n\nDeeper.\n\n")
  end
end
