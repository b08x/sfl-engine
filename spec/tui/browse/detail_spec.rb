# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe SFL::TUI::Browse::Detail do
  let(:state) { TUISpecSupport.browse_state }

  def at(id) = state.with(cursor: TUISpecSupport.row_of(state, id))

  # Fact 29
  it "shows a content-review item's generated text, reason and source file" do
    lines = described_class.lines(at("s:paper.md#method"))

    expect(lines).to include("Content review: pending (image)", "Reason: image", "Source file: /data/figure.png",
      "A chart of results.")
  end

  # Fact 33: annotation review badge and confidence, read-only.
  it "shows a clause's pending annotation review with its confidence and no actions" do
    lines = described_class.lines(at("s:paper.md#background").with(focus: :clauses))

    expect(lines).to include("Background one.", "[annotation review: pending] confidence 0.42 (read-only)")
    expect(lines.join).not_to match(/accept|reject/i)
  end

  it "shows a section without a review item, a document, and an empty corpus" do
    expect(described_class.lines(at("s:paper.md#intro")).last).to include("section paper.md#intro")
    expect(described_class.lines(at("d:10")).last).to include("document_key=paper.md")
    expect(described_class.lines(SFL::TUI::Browse::State.initial).first).to include("Nothing to show")
  end

  it "shows n/a for an annotation review without a confidence" do
    lines = described_class.lines(at("s:talk.srt#turn-2").with(focus: :clauses))

    expect(lines.last).to eq("[annotation review: accepted] confidence n/a (read-only)")
  end
end
