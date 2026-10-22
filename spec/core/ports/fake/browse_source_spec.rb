# frozen_string_literal: true

require_relative "../../../tui/spec_helper"

RSpec.describe SFL::Core::Ports::Fake::BrowseSource do
  subject(:source) { TUISpecSupport.source }

  it "serves collections, documents, sections and clauses from nested hashes" do
    expect(source.collections.map { |row| row[:name] }).to eq(%w[papers notes])
    expect(source.documents(1).map { |row| row[:document_key] }).to eq(["paper.md", "talk.srt"])
    expect(source.sections(10).first[:children].first[:section_id]).to eq("paper.md#background")
    expect(source.clauses("paper.md#method")).to eq([{ section_id: "paper.md#method" }.merge(TUISpecSupport.clause("m1", "Method one."))])
  end

  it "locates sections, nested ones included" do
    expect(source.locate(["paper.md#background", "missing"])).to eq(
      "paper.md#background" => { collection: "papers", document_key: "paper.md", source_path: "/data/paper.md", label: "Background" }
    )
  end

  it "returns review state and updates a review's status" do
    source.update_review("r1", status: "approved")

    expect(source.content_reviews.first[:status]).to eq("approved")
    expect(source.annotation_reviews.keys).to eq(%w[b1 t2])
  end
end
