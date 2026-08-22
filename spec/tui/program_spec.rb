# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe SFL::TUI::Program do
  subject(:program) { described_class.new(context:) }

  let(:context) { TUISpecSupport.context(width: 120, height: 40) }

  # Real KeyMessages, not doubles: the whole routing contract is keyed off
  # KeyMessage#to_s, and a double would let a wrong key name pass forever.
  # `runes` is an Array of CODEPOINTS (the gem packs it with "U*"), and
  # key_type -1 is what a printable rune arrives as — both confirmed against a
  # PTY-driven probe, not assumed.
  def rune_key(char, alt: false)
    Bubbletea::KeyMessage.new(key_type: -1, runes: char.unpack("U*"), alt:)
  end

  def ctrl_c = Bubbletea::KeyMessage.new(key_type: 3)

  it "starts on the Query Console" do
    expect(program.active_workspace.title).to eq("Query Console")
  end

  it "builds one shell per workspace in plan order" do
    expect(program.workspaces.map(&:title))
      .to eq(["Query Console", "Review Queues", "Corpus Browser", "Board"])
  end

  describe "#init" do
    it "returns the model and a single command slot, never an Array of commands" do
      model, command = program.init

      expect(model).to be_a(described_class)
      expect(command).to be_nil
    end
  end

  describe "#update" do
    it "quits on ctrl+c, which only ever arrives as a KeyMessage" do
      _model, command = program.update(ctrl_c)

      expect(command).to be_a(Bubbletea::QuitCommand)
    end

    it "quits on q" do
      _model, command = program.update(rune_key("q"))

      expect(command).to be_a(Bubbletea::QuitCommand)
    end

    it "switches workspace on alt+3 and back on alt+1" do
      switched, = program.update(rune_key("3", alt: true))
      back, = switched.update(rune_key("1", alt: true))

      expect(switched.active_workspace.title).to eq("Corpus Browser")
      expect(back.active_workspace.title).to eq("Query Console")
    end

    it "leaves the receiver untouched when switching" do
      program.update(rune_key("3", alt: true))

      expect(program.active_index).to eq(0)
    end

    it "resizes its context from a WindowSizeMessage" do
      resized, = program.update(Bubbletea::WindowSizeMessage.new(width: 200, height: 60))

      expect([resized.context.width, resized.context.height]).to eq([200, 60])
    end

    it "renders a Failed message as an explicit error state" do
      failed, = program.update(SFL::TUI::Messages::Failed.new(:retrieval, "pg down"))

      expect(failed.error).to eq("retrieval: pg down")
      expect(failed.view).to include("pg down")
    end

    it "clears the error state on a workspace switch" do
      failed, = program.update(SFL::TUI::Messages::Failed.new(:retrieval, "pg down"))
      switched, = failed.update(rune_key("3", alt: true))

      expect(switched.error).to be_nil
    end
  end

  describe "#view" do
    it "labels every workspace tab" do
      expect(program.view).to include("Query Console", "Review Queues", "Corpus Browser", "Board")
    end

    it "fits the terminal exactly, for every workspace" do
      4.times do |index|
        rendered = described_class.new(context:, active_index: index).view

        expect(Lipgloss.width(rendered)).to be <= context.width
        expect(Lipgloss.height(rendered)).to be <= context.height
      end
    end

    it "still fits a terminal at the minimum supported size" do
      tiny = described_class.new(context: TUISpecSupport.context(width: 40, height: 10)).view

      expect(Lipgloss.width(tiny)).to be <= 40
      expect(Lipgloss.height(tiny)).to be <= 10
    end

    # The regression this guards: a Failed detail built from an exception
    # message (PG/Sequel routinely embed newlines) rendered a THREE-row status
    # bar at 40 columns, so the frame measured 12 rows in a 10-row terminal —
    # the wrapped chrome row pushes the body down and desyncs the renderer.
    # Fixed in two places: Messages::Failed collapses whitespace, and
    # Program#clamp caps every chrome row at max_height(1).
    it "keeps the frame at exactly the chrome + body height with a multi-line, over-long error" do
      tiny = TUISpecSupport.context(width: 40, height: 10)
      detail = "PG::ConnectionBad: could not connect to server\n\tis the server running on port 5432?\n#{'detail ' * 60}"
      failed, = described_class.new(context: tiny).update(SFL::TUI::Messages::Failed.new(:retrieval, detail))

      rendered = failed.view

      expect(Lipgloss.height(rendered)).to eq(SFL::TUI::Layout::CHROME_HEIGHT + SFL::TUI::Layout.body_height(tiny))
      expect(Lipgloss.height(rendered)).to eq(10)
      expect(Lipgloss.width(rendered)).to be <= 40
    end

    it "collapses the newlines out of the error detail rather than relying on truncation alone" do
      failed, = program.update(SFL::TUI::Messages::Failed.new(:retrieval, "line one\nline two"))

      expect(failed.error).to eq("retrieval: line one line two")
    end

    it "shows the keybinding hint in the status bar" do
      expect(program.view).to include("alt+1..4")
    end
  end
end
