# frozen_string_literal: true

require "spec_helper"
require "ruby_llm"

# Fact 55: the ruby_llm registry, without the providers listed by their own catalogs.
RSpec.describe SFL::LLM::Catalogs::RubyLLMCatalog do
  def info(id, provider, output: ["text"], input: ["text"], capabilities: [])
    RubyLLM::Model::Info.new(id:, name: id.upcase, provider:, context_window: 1000, capabilities:,
      modalities: { input:, output: }, pricing: { text_tokens: { standard: { input_per_million: 1.5 } } })
  end

  let(:registry) do
    [
      info("gpt-x", "openai", input: %w[text image], capabilities: ["function_calling"]),
      info("embed-x", "openai", output: ["embeddings"]),
      info("or-model", "openrouter"),
      info("local", "ollama"),
    ]
  end
  let(:catalog) { described_class.new(registry: -> { registry }) }

  it "maps registry models to entries with chat, embedding and vision capabilities" do
    entries = catalog.fetch

    expect(entries.map { |entry| [entry.provider, entry.model_id, entry.capabilities] }).to eq([
      ["openai", "gpt-x", %w[chat vision function_calling]],
      ["openai", "embed-x", ["embedding"]],
    ])
    expect(entries.first).to have_attributes(name: "GPT-X", context_window: 1000)
    expect(entries.first.pricing).to include(:text_tokens)
  end

  it "is authoritative for the providers it listed" do
    expect([catalog.name, catalog.providers(catalog.fetch)]).to eq(["ruby_llm", ["openai"]])
  end
end
