# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::ChatgptExportSource do
  subject(:source) { described_class.new(path) }

  let(:path) { "spec/fixtures/loaders/chatgpt_conversations.json" }

  it "is a Loaders::Source" do
    expect(source).to be_a(SFL::Core::Loaders::Source)
  end

  it "walks the mapping tree into a chronological User/ChatGPT turn sequence, skipping the system turn" do
    units = source.units

    expect(units.map(&:document_id)).to eq(%w[convo-1#turn-0 convo-1#turn-1])
    expect(units.map(&:speaker)).to eq(%w[User ChatGPT])
    expect(units.map(&:is_user)).to eq([true, false])
    expect(units.first.text).to eq("What is reciprocal rank fusion?")
  end

  it "produces no units for a conversation whose mapping has no real messages" do
    units = source.units

    expect(units.map { |u| u.metadata["conversation_id"] }).not_to include("convo-2")
  end

  it "derives sent_at from the message's create_time" do
    unit = source.units.first

    expect(unit.sent_at).to eq(Time.at(1_780_000_001))
  end
end
