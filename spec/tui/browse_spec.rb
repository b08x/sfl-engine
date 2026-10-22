# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe SFL::TUI::Browse do
  let(:state) { TUISpecSupport.browse_state }

  it "names section and clause nodes" do
    expect(described_class.section_node("a#b")).to eq("s:a#b")
    expect(described_class.clause_node("x")).to eq("k:x")
  end

  it "handles its own result messages only" do
    expect(described_class.handles?(SFL::TUI::Messages::Reviewed.new("x"))).to be(true)
    expect(described_class.handles?(SFL::TUI::Messages::SearchResults.new(query: "q", rows: []))).to be(false)
  end

  # Fact 40: the status line shows selected section and clause counts.
  it "reports selected sections and clauses as its status" do
    selected = state.with(selection: state.selection.select(state.tree, "d:11"))

    expect(described_class.status(selected)).to eq("selected: 2 sections, 2 clauses")
  end

  it "captures keys and shows the format keys while the export choice is open" do
    open = state.with(overlay: :export)

    expect(described_class.capturing?(open)).to be(true)
    expect(described_class.help(open)).to eq(described_class::OVERLAY_HELP)
    expect(described_class.capturing?(state)).to be(false)
  end

  it "starts empty and loads on init" do
    expect(described_class.initial.rows).to eq([])
    expect(described_class.init(SFL::TUI::Services.null).call).to be_a(SFL::TUI::Messages::BrowseLoaded)
  end
end
