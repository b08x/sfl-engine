# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe SFL::TUI::KeyName do
  def name(code, modifiers = []) = described_class.call(RatatuiRuby::Event::Key.new(code:, modifiers:))

  it "names plain, special and modified keys" do
    expect(name("a")).to eq("a")
    expect(name(" ")).to eq(" ")
    expect(name("enter")).to eq("enter")
    expect(name("c", ["ctrl"])).to eq("ctrl_c")
  end

  it "drops shift from single characters but keeps it on special keys" do
    expect(name("A", ["shift"])).to eq("A")
    expect(name("tab", ["shift"])).to eq("shift_tab")
  end
end
