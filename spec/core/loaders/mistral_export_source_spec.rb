# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::MistralExportSource do
  it "is a Loaders::Source" do
    expect(described_class.new("spec/fixtures/loaders/mistral")).to be_a(SFL::Core::Loaders::Source)
  end

  it "reads every chat-*.json file in a directory, skipping conversations with no non-blank turns" do
    units = described_class.new("spec/fixtures/loaders/mistral").units

    expect(units.map { |u| u.metadata["conversation_id"] }.uniq).to eq(["aaa"])
    expect(units.map(&:speaker)).to eq(%w[User Mistral])
  end

  it "reads a single chat file directly" do
    units = described_class.new("spec/fixtures/loaders/mistral/chat-aaa.json").units

    expect(units.size).to eq(2)
    expect(units.first.text).to eq("Roast my Ansible playbooks.")
  end
end
