# frozen_string_literal: true

require "spec_helper"

# Fact 55: the OpenRouter listing, from a recorded /api/v1/models reply.
RSpec.describe SFL::LLM::Catalogs::OpenRouterCatalog do
  let(:body) { File.read(File.expand_path("../../fixtures/models/openrouter_models.json", __dir__)) }
  let(:requests) { [] }
  let(:http) { -> (url, headers) { (requests << [url, headers]) && body } }

  it "lists each model with context window, pricing and modality capabilities" do
    entries = described_class.new(http:).fetch

    expect(entries.map { |entry| [entry.model_id, entry.capabilities] }).to eq([
      ["upstage/solar-pro4", ["chat"]],
      ["google/gemini-2.5-flash", %w[chat vision]],
    ])
    expect(entries.first).to have_attributes(provider: "openrouter", name: "Upstage: Solar Pro 4", context_window: 65_536,
      pricing: { "prompt" => "0.00000015", "completion" => "0.0000006" })
    expect(requests).to eq([[described_class::URL, {}]])
  end

  it "sends the API key as a bearer token when given" do
    described_class.new(api_key: "or-key", http:).fetch

    expect(requests.first.last).to eq("Authorization" => "Bearer or-key")
  end

  it "marks embedding models from their output modality" do
    reply = { data: [{ id: "e", architecture: { input_modalities: ["text"], output_modalities: ["embeddings"] } }] }.to_json
    entry = described_class.new(http: -> (*) { reply }).fetch.first

    expect(entry.capabilities).to eq(["embedding"])
    expect(entry.pricing).to eq({})
  end

  it "is authoritative for the openrouter provider" do
    catalog = described_class.new(http:)

    expect([catalog.name, catalog.providers([])]).to eq(["openrouter", ["openrouter"]])
  end
end
