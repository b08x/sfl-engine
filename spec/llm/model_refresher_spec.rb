# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::LLM::ModelRefresher do
  def entry(provider, model_id)
    SFL::Core::Ports::ModelCatalog::Entry.new(provider:, model_id:, name: model_id, context_window: nil,
      capabilities: ["chat"], pricing: {})
  end

  let(:store) do
    SFL::Core::Ports::Fake::ModelStore.new(models: [
      { provider: "ollama", model_id: "old", available: true },
      { provider: "openrouter", model_id: "kept", available: true },
    ])
  end
  let(:logger) { instance_spy(SFL::Core::Ports::Logger) }
  let(:catalogs) do
    [
      SFL::Core::Ports::Fake::ModelCatalog.new(name: "ollama", entries: [entry("ollama", "new")], providers: ["ollama"]),
      SFL::Core::Ports::Fake::ModelCatalog.new(name: "openrouter", error: SocketError.new("no route")),
    ]
  end

  it "syncs each catalog and reports its counts" do
    outcomes = described_class.new(catalogs:, store:, logger:).call

    expect(outcomes.map(&:to_s)).to eq(["ollama: 1 listed, 1 unavailable", "openrouter: failed (SocketError: no route)"])
    expect(logger).to have_received(:info).with("models refreshed", catalog: "ollama", upserted: 1, unavailable: 1)
  end

  it "leaves a failed provider's rows untouched and logs the failure (fact 56)" do
    described_class.new(catalogs:, store:, logger:).call

    expect(store.list.to_h { |row| [row[:model_id], row[:available]] }).to eq("new" => true, "old" => false, "kept" => true)
    expect(logger).to have_received(:error).with("model refresh failed", catalog: "openrouter", error: "SocketError: no route")
  end

  it "reports a failed catalog with zero counts" do
    outcome = described_class.new(catalogs: [catalogs.last], store:, logger:).call.first

    expect(outcome).to eq(SFL::LLM::ModelRefresher::Outcome.new(catalog: "openrouter", upserted: 0, unavailable: 0,
      error: "SocketError: no route"))
  end

  it "asks the catalog which providers its fetched entries cover" do
    catalog = SFL::Core::Ports::Fake::ModelCatalog.new(name: "gemini", entries: [entry("gemini", "g1")])
    store = SFL::Core::Ports::Fake::ModelStore.new(models: [{ provider: "gemini", model_id: "g0", available: true }])
    outcome = described_class.new(catalogs: [catalog], store:, logger:).call.first

    expect(outcome.error).to be_nil
    expect(store.list.to_h { |row| [row[:model_id], row[:available]] }).to eq("g1" => true, "g0" => false)
  end
end
