# frozen_string_literal: true

require "spec_helper"

# Facts 54, 56 and 57 against Postgres.
RSpec.describe SFL::Store::PgModelRepository do
  subject(:repo) { described_class.new(db, clock: -> { clock_time.first }) }

  let(:db) { SFL::Store::StoreTestDb.db }
  let(:now) { Time.utc(2026, 10, 17, 12) }
  let(:clock_time) { [now] }

  before { SFL::Store::StoreTestDb.clean! }

  def entry(provider, model_id, capabilities: ["chat"], pricing: {})
    SFL::Core::Ports::ModelCatalog::Entry.new(provider:, model_id:, name: model_id.upcase, context_window: 4096,
      capabilities:, pricing:)
  end

  it "stores provider, model id, context window, capabilities, pricing, availability and fetch time (fact 54)" do
    repo.sync([entry("openrouter", "a/b", capabilities: %w[chat vision], pricing: { "prompt" => "0.1" })],
      providers: ["openrouter"])

    expect(repo.list).to eq([
{
  provider: "openrouter",
  model_id: "a/b",
  name: "A/B",
  context_window: 4096,
  capabilities: %w[chat vision],
  pricing: { "prompt" => "0.1" },
  available: true,
  fetched_at: now,
},
])
  end

  it "marks a model missing from its provider's latest listing unavailable and keeps the row (fact 56)" do
    repo.sync([entry("ollama", "a"), entry("ollama", "b"), entry("openai", "c")], providers: %w[ollama openai])
    clock_time[0] = now + 60

    expect(repo.sync([entry("ollama", "a")], providers: ["ollama"])).to eq(upserted: 1, unavailable: 1)
    expect(repo.list.map { |row| row.values_at(:provider, :model_id, :available) }).to eq([
      ["ollama", "a", true], ["ollama", "b", false], ["openai", "c", true]
    ])
    expect(repo.list.first[:fetched_at]).to eq(now + 60)
  end

  it "marks every model of a provider unavailable when its listing is empty, and available again when relisted" do
    repo.sync([entry("ollama", "a")], providers: ["ollama"])

    expect(repo.sync([], providers: ["ollama"])).to eq(upserted: 0, unavailable: 1)
    repo.sync([entry("ollama", "a")], providers: ["ollama"])
    expect(repo.list.map { |row| row[:available] }).to eq([true])
  end

  it "holds at most one assignment per task, replacing the earlier one (fact 57)" do
    repo.assign(:embedding, provider: "ollama", model_id: "a")
    clock_time[0] = now + 5
    repo.assign("embedding", provider: :ollama, model_id: "b")
    repo.assign(:loader_drafting, provider: "openrouter", model_id: "c")

    expect(repo.assignments).to eq(embedding: { provider: "ollama", model_id: "b" },
      loader_drafting: { provider: "openrouter", model_id: "c" })
    expect(db[:task_models].where(task: "embedding").get(:updated_at)).to eq(now + 5)
  end
end
