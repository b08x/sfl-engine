# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe SFL::TUI::Browse::State do
  let(:state) { TUISpecSupport.browse_state }

  def at(state, id) = state.with(cursor: TUISpecSupport.row_of(state, id))

  # Fact 26 (layout is checked by hand): the tree lists collections, documents and nested sections.
  it "lists collections, documents and nested sections with depth, and no clauses" do
    expect(state.rows.map(&:id)).to eq(
      [
        "c:1",
        "d:10",
        "s:paper.md#intro",
        "s:paper.md#background",
        "s:paper.md#method",
        "d:11",
        "s:talk.srt#turn-1",
        "s:talk.srt#turn-2",
        "c:2",
        "d:20",
        "s:note.txt#0",
]
    )
    expect(state.rows.map(&:depth).uniq.sort).to eq([0, 1, 2, 3])
  end

  it "hides the children of a collapsed row" do
    collapsed = state.with(expanded: state.expanded - ["d:10"])

    expect(collapsed.rows.map(&:id)).not_to include("s:paper.md#intro")
  end

  it "lists the focused section's clauses" do
    expect(at(state, "s:paper.md#intro").clause_rows.map(&:label)).to eq(["Intro one.", "Intro two."])
    expect(at(state, "d:10").clause_rows).to eq([])
  end

  # Fact 27: the status filter narrows the tree and the clause list.
  it "keeps only rows on a path to a section or loaded clause with the filtered status" do
    pending = state.with(filter: "pending")

    # Intro shows because its child Background holds a clause with a pending annotation review.
    expect(pending.rows.map(&:id)).to eq(["c:1", "d:10", "s:paper.md#intro", "s:paper.md#background", "s:paper.md#method"])
    expect(state.with(filter: "rejected").rows.map(&:id)).to eq(["c:1", "d:11", "s:talk.srt#turn-1"])
  end

  it "filters clauses by their annotation status or their section's status" do
    accepted = at(state.with(filter: "accepted"), "s:talk.srt#turn-2")
    rejected = at(state.with(filter: "rejected"), "s:talk.srt#turn-1")

    expect(accepted.clause_rows.map(&:label)).to eq(["Hi Alice."])
    expect(rejected.clause_rows.map(&:label)).to eq(["Hello there."])
  end

  it "gives the level of the focused row in the focused pane" do
    expect(at(state, "d:11").level_ids).to eq(["d:10", "d:11", "d:20"])
    expect(at(state, "s:paper.md#intro").with(focus: :clauses).level_ids).to eq(["k:i1", "k:i2"])
  end

  it "finds the focused section's content-review item" do
    expect(at(state, "s:paper.md#method").review_item[:id]).to eq("r1")
    expect(at(state, "d:10").review_item).to be_nil
  end

  describe "#picks" do
    it "orders picks by document and ordinal, whole sections with nil clause ids" do
      selection = state.selection.select(state.tree, "c:1")
      picks = state.with(selection:).picks

      expect(picks.map(&:section_id)).to eq(
        ["paper.md#intro", "paper.md#background", "paper.md#method", "talk.srt#turn-1", "talk.srt#turn-2"]
      )
      expect(picks.map(&:clause_ids).uniq).to eq([nil])
      expect(picks.first).to have_attributes(collection: "papers", document_key: "paper.md", title: "Paper", depth: 0)
      expect(picks[1]).to have_attributes(path: %w[Intro Background], depth: 1)
    end

    it "lists the chosen clause ids of a partly selected section" do
      selection = state.selection.select(state.tree, "k:i2")

      expect(state.with(selection:).picks.map { |pick| [pick.section_id, pick.clause_ids] }).to eq([["paper.md#intro", ["i2"]]])
    end
  end
end
