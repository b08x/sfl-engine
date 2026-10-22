# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Fake::ModelStore do
  let(:now) { Time.utc(2026, 10, 17) }
  let(:store) do
    described_class.new(models: [
      { provider: "ollama", model_id: "gone", available: true },
      { provider: "openai", model_id: "other", available: true },
], clock: -> { now })
  end

  def entry(model_id)
    SFL::Core::Ports::ModelCatalog::Entry.new(provider: "ollama", model_id:, name: model_id, context_window: nil,
      capabilities: ["chat"], pricing: {})
  end

  it "upserts listed models and flags the provider's missing ones without deleting them" do
    expect(store.sync([entry("new")], providers: ["ollama"])).to eq(upserted: 1, unavailable: 1)
    expect(store.list.map { |row| row.values_at(:provider, :model_id, :available) }).to eq([
      ["ollama", "gone", false], ["ollama", "new", true], ["openai", "other", true]
    ])
    expect(store.list[1][:fetched_at]).to eq(now)
  end

  it "keeps one assignment per task" do
    store.assign("embedding", provider: "ollama", model_id: "a")
    store.assign(:embedding, provider: "ollama", model_id: "b")

    expect(store.assignments).to eq(embedding: { provider: "ollama", model_id: "b" })
  end
end
