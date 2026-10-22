# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe SFL::TUI::Program do
  let(:services) { SFL::TUI::Services.null(source: TUISpecSupport.source) }
  let(:state) { described_class.initial }

  def press(state, key) = described_class.update(state, TUISpecSupport.key(key), services)

  # Facts 24-25: ratatui tabs Browse, Search, Runs, Models; no Board.
  it "has the tabs Browse, Search, Runs and Models and no Board" do
    expect(described_class::TABS.map { |tab| tab::TITLE }).to eq(%w[Browse Search Runs Models])
  end

  it "switches tabs with the digit keys and quits with q or ctrl_c" do
    expect(press(state, "3").first.active).to eq(2)
    expect(press(state, "q").first.quit).to be(true)
    expect(press(state, "ctrl_c").first.quit).to be(true)
  end

  it "sends keys to the active tab while it captures input, except ctrl_c" do
    typing = described_class.update(press(state, "2").first, TUISpecSupport.key("/"), services).first

    expect(press(typing, "q").first).to have_attributes(quit: false, active: 1)
    expect(press(typing, "1").first.active_state.query).to eq("1")
    expect(press(typing, "ctrl_c").first.quit).to be(true)
  end

  it "routes results to the tab that handles them" do
    loaded = SFL::TUI::Browse::Commands.load(services).call
    next_state, = described_class.update(state, loaded, services)

    expect(next_state.tabs.first.tree.roots).to eq(["c:1", "c:2"])
    expect(described_class.update(state, Object.new, services)).to eq([state, nil])
  end

  # Fact 44: the export path is shown in the status line.
  it "shows notices, failures and the export path on the status line" do
    exported, = described_class.update(state, SFL::TUI::Messages::Exported.new(path: "/out/papers-1.md", count: 2), services)
    failed, = described_class.update(state, SFL::TUI::Messages::Failed.new(:browse, "boom"), services)
    reviewed, = described_class.update(state, SFL::TUI::Messages::Reviewed.new("approve: s"), services)

    expect(described_class.status_line(exported)).to eq("selected: 0 sections, 0 clauses | exported 2 clauses to /out/papers-1.md")
    expect(failed).to have_attributes(status: "browse: boom", error: true)
    expect(reviewed.status).to eq("approve: s")
  end

  it "shows a plain notice and clears the error flag" do
    failed, = described_class.update(state, SFL::TUI::Messages::Failed.new(:browse, "boom"), services)
    notice, = described_class.update(failed, SFL::TUI::Messages::Status.new("loaded"), services)

    expect(notice).to have_attributes(status: "loaded", error: false)
  end

  # Fact 37 (checked by hand as well): the help line lists the active tab's keys and the global ones.
  it "lists the active tab's keys and the global keys in the help line" do
    help = described_class.help(state)

    %w[Space a Esc f e A R E o].each { |key| expect(help).to include(key) }
    expect(help).to include("1-4 switch tab", "i ingest", "q quit")
    expect(described_class.help(state.with(active: 1))).to include("/ type query")
  end

  it "returns each tab's first command" do
    expect(described_class.init(services).size).to eq(3)
  end

  describe "the ingest launcher" do
    let(:loaded) { described_class.update(state, SFL::TUI::Browse::Commands.load(services).call, services).first }

    def type(state, text) = text.chars.reduce(state) { |acc, char| press(acc, char).first }

    # Fact 68: an overlay over any tab, offering Browse's collections.
    it "opens with i over any tab, offers the loaded collections, and takes every key but ctrl_c" do
      opened = press(press(loaded, "3").first, "i").first

      expect(opened.launcher.collections).to eq(%w[papers notes])
      expect(opened.active).to eq(2)
      expect(type(opened, "q1").launcher.path).to eq("q1")
      expect(described_class.help(opened)).to include("Enter start", "Esc cancel")
      expect(press(opened, "esc").first.launcher).to be_nil
      expect(press(opened, "ctrl_c").first.quit).to be(true)
    end

    it "does not open while a tab captures typing" do
      typing = described_class.update(press(state, "2").first, TUISpecSupport.key("/"), services).first

      expect(press(typing, "i").first.launcher).to be_nil
    end

    it "closes on Enter and returns the start command" do
      opened = type(press(loaded, "i").first, Dir.pwd)
      closed, command = press(opened, "enter")

      expect(closed.launcher).to be_nil
      expect(command).to be_a(Proc)
    end

    # Fact 70: a detached ingest is followed on the Runs tab.
    it "moves to the Runs tab and reloads it after a detached launch, and only notes a tab launch" do
      detached, reload = described_class.update(state, SFL::TUI::Messages::Launched.new(text: "started", detached: true), services)
      in_tab, none = described_class.update(state, SFL::TUI::Messages::Launched.new(text: "in tab", detached: false), services)

      expect(detached).to have_attributes(active: 2, status: "started")
      expect(reload.call).to be_a(SFL::TUI::Messages::RunsLoaded)
      expect(in_tab).to have_attributes(active: 0, status: "in tab")
      expect(none).to be_nil
    end

    it "draws the launcher over the active tab" do
      opened = press(loaded, "i").first
      lines = TUISpecSupport.render(width: 100, height: 20) { |frame, tui| described_class.render(opened, frame, tui) }

      expect(lines.join("\n")).to include("Ingest", "> Path", "Existing collections: papers, notes")
    end
  end

  it "draws the tab bar, the active tab, the status line and the help line" do
    lines = TUISpecSupport.render(width: 100, height: 12) { |frame, tui| described_class.render(state, frame, tui) }

    expect(lines.first).to include("1 Browse", "2 Search", "3 Runs", "4 Models")
    expect(lines[-3]).to include("selected: 0 sections, 0 clauses")
    expect(lines[-2]).to include("↑/↓ move")
  end
end
