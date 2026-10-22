# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe SFL::TUI::Messages do
  it "collapses whitespace in a failure so the status line stays one row" do
    failed = described_class::Failed.new(:browse, "PG::Error\n  could not   connect")

    expect(failed.to_s).to eq("browse: PG::Error could not connect")
    expect(failed).to be_frozen
  end

  it "compares value messages by their fields" do
    expect(described_class::Key.new("a")).to eq(described_class::Key.new(key: "a"))
    expect(described_class::Exported.new(path: "p", count: 1).count).to eq(1)
  end
end
