# frozen_string_literal: true

require_relative "../spec_helper"

# Fact 26 is checked by hand; this spec pins the three-pane layout in the buffer.
RSpec.describe SFL::TUI::Browse::View do
  let(:state) do
    loaded = TUISpecSupport.browse_state
    loaded.with(cursor: TUISpecSupport.row_of(loaded, "s:paper.md#method"))
  end

  def draw(state) = TUISpecSupport.render(width: 120, height: 16) { |frame, tui| described_class.render(state, frame, frame.area, tui) }

  it "draws the tree on the left, clauses in the middle and detail on the right" do
    first, second = draw(state)

    expect(first).to match(/┌Tree \[all\].*┌Clauses.*┌Detail/)
    expect(second).to match(/papers.*Method one\..*Method/)
  end

  it "draws the export format choice over the panes" do
    lines = draw(state.with(overlay: :export)).join("\n")

    expect(lines).to include("Export selected clauses as:", "j  JSONL", "m  Markdown")
  end

  it "shows the active filter in the tree title" do
    expect(draw(state.with(filter: "pending")).first).to include("Tree [pending review]")
  end
end
