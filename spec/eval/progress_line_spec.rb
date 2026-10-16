# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Eval::ProgressLine do
  describe ".parse" do
    it "returns turn and total for a progress line" do
      expect(described_class.parse("progress turn=3 total=12")).to eq(turn: 3, total: 12)
    end

    it "accepts a trailing newline" do
      expect(described_class.parse("progress turn=1 total=2\n")).to eq(turn: 1, total: 2)
    end

    it "returns nil for log text, including journald-style and stderr log lines" do
      ["pass_one completed document_id=d1", "INFO pipeline completed run_id=abc", "", "progress turn=x total=2"].each do |text|
        expect(described_class.parse(text)).to be_nil
      end
    end

    it "returns nil for nil" do
      expect(described_class.parse(nil)).to be_nil
    end
  end
end
