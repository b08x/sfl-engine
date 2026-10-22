# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe SFL::TUI::Browse::Rows do
  let(:state) { TUISpecSupport.browse_state }

  # Fact 28: a section with a pending content-review item shows a badge.
  it "badges a section with a pending content-review item and not one whose item is decided" do
    method = state.tree.node("s:paper.md#method")
    turn = state.tree.node("s:talk.srt#turn-1")

    expect(described_class.tree_label(state, method)).to eq("      [ ] Method [R]")
    expect(described_class.tree_label(state, turn)).not_to include("[R]")
  end

  # Fact 39: full and partial marks.
  it "marks full and partial selection and the expansion state" do
    selected = state.with(selection: state.selection.select(state.tree, "s:paper.md#method"))

    expect(described_class.tree_label(selected, state.tree.node("d:10"))).to eq("  ▾ [~] Paper")
    expect(described_class.tree_label(selected, state.tree.node("s:paper.md#method"))).to include("[x] Method")
    collapsed = state.with(expanded: Set.new)
    expect(described_class.tree_label(collapsed, state.tree.node("c:1"))).to eq("▸ [ ] papers")
  end

  # Fact 33: a clause with a pending annotation review shows a badge.
  it "badges a clause with a pending annotation review" do
    expect(described_class.clause_label(state, state.tree.node("k:b1"))).to eq("[ ] [A] Background one.")
    expect(described_class.clause_label(state, state.tree.node("k:t2"))).to eq("[ ] Hi Alice.")
  end
end
