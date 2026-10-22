# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe SFL::TUI::Browse::Reviews do
  subject(:reviews) { TUISpecSupport.reviews }

  it "maps content-review statuses to the filter vocabulary" do
    expect(reviews.section_status("paper.md#method")).to eq("pending")
    expect(reviews.section_status("talk.srt#turn-1")).to eq("rejected")
    expect(reviews.section_status("paper.md#intro")).to be_nil
  end

  it "prefers a section's pending item over its decided ones" do
    rows = [
      { id: "old", section_id: "s", status: "approved" },
      { id: "new", section_id: "s", status: "pending" },
    ]

    expect(described_class.new(content: rows).item("s")[:id]).to eq("new")
    expect(described_class.new(content: rows.first(1)).section_status("s")).to eq("accepted")
  end

  it "reports annotation review per clause and falls back to the section status" do
    expect(reviews.annotation_pending?("b1")).to be(true)
    expect(reviews.annotation("b1")[:confidence]).to eq(0.42)
    expect(reviews.clause_status("t2", "talk.srt#turn-2")).to eq("accepted")
    expect(reviews.clause_status("m1", "paper.md#method")).to eq("pending")
  end
end
