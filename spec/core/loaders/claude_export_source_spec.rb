# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::ClaudeExportSource do
  subject(:source) { described_class.new(path) }

  let(:path) { "spec/fixtures/loaders/claude_conversations.json" }

  it "is a Loaders::Source" do
    expect(source).to be_a(SFL::Core::Loaders::Source)
  end

  it "yields Human/Assistant turns for a conversation" do
    units = source.units.select { |u| u.metadata["conversation_id"] == "convo-1" }

    expect(units.map(&:speaker)).to eq(%w[Human Assistant])
    expect(units.map(&:is_user)).to eq([true, false])
  end

  it "prefers .content text blocks over the stale flat .text field" do
    unit = source.units.find { |u| u.speaker == "Assistant" && u.metadata["conversation_id"] == "convo-1" }

    expect(unit.text).to eq("It's a race condition in the setup block.")
    expect(unit.text).not_to eq("fallback text")
  end

  it "skips a whitespace-only human turn but keeps the assistant reply that follows" do
    units = source.units.select { |u| u.metadata["conversation_id"] == "convo-2" }

    expect(units.map(&:speaker)).to eq(["Assistant"])
  end

  describe "#memories" do
    it "returns an empty Array when no memories_path was given" do
      expect(source.memories).to eq([])
    end
  end
end
