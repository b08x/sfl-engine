# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe SFL::TUI::Layout do
  describe ".columns" do
    it "returns widths summing to exactly the available width" do
      expect(described_class.columns(120, 0.25, 0.50, 0.25).sum).to eq(120)
    end

    it "gives the remainder to the last column rather than losing it to rounding" do
      expect(described_class.columns(101, 0.30, 0.45, 0.25)).to eq([30, 45, 26])
    end

    it "never emits a zero-width column on a narrow terminal" do
      expect(described_class.columns(4, 0.25, 0.25, 0.25, 0.25)).to all(be_positive)
    end
  end

  describe ".body_height" do
    it "reserves the tab bar and status bar rows" do
      expect(described_class.body_height(TUISpecSupport.context(height: 40))).to eq(38)
    end
  end
end
