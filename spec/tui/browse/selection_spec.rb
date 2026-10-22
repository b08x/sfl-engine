# frozen_string_literal: true

require_relative "../spec_helper"

# Facts 38-40: toggle, subtree selection, partial parents, counts.
RSpec.describe SFL::TUI::Browse::Selection do
  let(:tree) { TUISpecSupport.browse_state.tree }
  let(:empty) { described_class.new }

  it "toggles a single row on and off at every level" do
    %w[c:2 d:11 s:paper.md#method k:i1].each do |id|
      on = empty.toggle(tree, id)

      expect(on.state(tree, id)).to eq(:full)
      expect(on.toggle(tree, id).state(tree, id)).to eq(:none)
    end
  end

  it "selects every descendant of a selected row, down to clauses" do
    selection = empty.select(tree, "c:1")

    expect(selection.ids).to include("d:10", "d:11", "s:paper.md#background", "k:b1", "k:t2")
  end

  it "marks a parent with only some descendants selected as partial" do
    selection = empty.select(tree, "s:paper.md#method")

    expect(selection.state(tree, "d:10")).to eq(:partial)
    expect(selection.state(tree, "c:1")).to eq(:partial)
    expect(selection.state(tree, "c:2")).to eq(:none)
  end

  it "makes a parent whole once all its children are selected" do
    selection = empty.select(tree, "k:i1").select(tree, "k:i2").select(tree, "s:paper.md#background")

    expect(selection.state(tree, "s:paper.md#intro")).to eq(:full)
  end

  it "does not make a section whole from its child sections while its own clauses are unknown" do
    bare = TUISpecSupport.tree
    selection = empty.select(bare, "s:paper.md#background")

    expect(selection.state(bare, "s:paper.md#intro")).to eq(:partial)
  end

  it "deselecting a row makes its ancestors partial" do
    selection = empty.select(tree, "d:10").deselect(tree, "k:i1")

    expect(selection.state(tree, "s:paper.md#intro")).to eq(:partial)
    expect(selection.state(tree, "d:10")).to eq(:partial)
    expect(selection.state(tree, "s:paper.md#method")).to eq(:full)
  end

  it "selects all given rows and clears" do
    selection = empty.select_all(tree, ["s:talk.srt#turn-1", "s:talk.srt#turn-2"])

    expect(selection.state(tree, "d:11")).to eq(:full)
    expect(selection.clear).to be_empty
  end

  it "counts selected sections and clauses, using clause_count for sections whose clauses are not loaded" do
    bare = TUISpecSupport.tree
    expect(empty.select(bare, "d:10").counts(bare)).to eq(sections: 3, clauses: 4)
    expect(empty.select(tree, "k:i1").counts(tree)).to eq(sections: 0, clauses: 1)
  end

  it "absorbs the clauses of a selected section once they load" do
    bare = TUISpecSupport.tree
    selection = empty.select(bare, "s:paper.md#method")
    loaded = bare.with_clauses("paper.md#method", TUISpecSupport.clauses["paper.md#method"])

    expect(selection.absorb(loaded, "s:paper.md#method").ids).to include("k:m1")
    expect(empty.absorb(loaded, "s:paper.md#method")).to be_empty
  end
end
