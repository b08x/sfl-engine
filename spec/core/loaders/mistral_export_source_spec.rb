# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::MistralExportSource do
  it "is a Loaders::Source" do
    expect(described_class.new(file_ref("spec/fixtures/loaders/mistral/chat-aaa.json"))).to be_a(SFL::Core::Loaders::Source)
  end

  it "reads a single chat file directly" do
    units = described_class.new(file_ref("spec/fixtures/loaders/mistral/chat-aaa.json")).units

    expect(units.size).to eq(2)
    expect(units.first.text).to eq("Roast my Ansible playbooks.")
  end
end
