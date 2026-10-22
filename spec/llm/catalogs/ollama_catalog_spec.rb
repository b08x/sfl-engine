# frozen_string_literal: true

require "spec_helper"

# Fact 55: the Ollama listing, from a recorded /api/tags reply.
RSpec.describe SFL::LLM::Catalogs::OllamaCatalog do
  let(:body) { File.read(File.expand_path("../../fixtures/models/ollama_tags.json", __dir__)) }
  let(:requests) { [] }
  let(:http) { -> (url, headers) { (requests << [url, headers]) && body } }
  let(:catalog) { described_class.new(base_url: "http://tinybot:11434/", http:) }

  it "lists each pulled model with capabilities read from its name" do
    entries = catalog.fetch

    expect(requests).to eq([["http://tinybot:11434/api/tags", {}]])
    expect(entries.map { |entry| [entry.model_id, entry.capabilities] }).to eq([
      ["llama3.2:latest", ["chat"]],
      ["embeddinggemma:latest", ["embedding"]],
      ["llava:7b", %w[chat vision]],
    ])
    expect(entries.first).to have_attributes(provider: "ollama", name: "llama3.2:latest", context_window: nil, pricing: {})
  end

  it "is authoritative for the ollama provider" do
    expect([catalog.name, catalog.providers([])]).to eq(["ollama", ["ollama"]])
  end

  it "raises when the reply has no models key" do
    expect { described_class.new(base_url: "http://x", http: -> (*) { "{}" }).fetch }.to raise_error(KeyError)
  end
end
