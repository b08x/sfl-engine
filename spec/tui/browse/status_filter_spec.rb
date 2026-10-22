# frozen_string_literal: true

require_relative "../spec_helper"

# Fact 27: all, pending review, accepted, rejected.
RSpec.describe SFL::TUI::Browse::StatusFilter do
  it "cycles all, pending review, accepted, rejected" do
    labels = described_class::VALUES.map { |value| described_class.label(value) }

    expect(labels).to eq(["all", "pending review", "accepted", "rejected"])
    expect(described_class.next("rejected")).to eq("all")
    expect(described_class.next("all")).to eq("pending")
  end

  it "matches everything under all and only the same status otherwise" do
    expect(described_class.match?("all", nil)).to be(true)
    expect(described_class.match?("pending", "pending")).to be(true)
    expect(described_class.match?("pending", nil)).to be(false)
  end
end
