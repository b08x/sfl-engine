# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe SFL::TUI::Launcher::View do
  let(:state) { SFL::TUI::Launcher.open(%w[papers notes]) }

  it "lists the three fields, marks the focused one and the existing collections" do
    lines = described_class.lines(state.with(path: "/data", collection: "papers", field: 1))

    expect(lines).to include("  Path        /data", "> Collection  papers  (existing)", "  Flags       ",
      "Existing collections: papers, notes")
  end

  it "labels a new name and the default, and shows the refusal" do
    expect(described_class.lines(state.with(collection: "fresh"))).to include(a_string_ending_with("fresh  (new)"))
    expect(described_class.lines(state)).to include(a_string_including("(default: the path's base name)"))
    expect(described_class.lines(state.with(error: "path is required")).last).to eq("! path is required")
  end

  it "draws an overlay box over the body" do
    lines = TUISpecSupport.render(width: 80, height: 14) do |frame, tui|
      frame.render_widget(tui.paragraph(text: "underneath " * 80, wrap: true), frame.area)
      described_class.render(state.with(path: "/data/talks"), frame, frame.area, tui)
    end

    expect(lines.join("\n")).to include("Ingest", "> Path        /data/talks", "Existing collections: papers, notes")
    expect(lines.first).to include("underneath")
    expect(lines[1]).to start_with("unde┌Ingest")
  end
end
