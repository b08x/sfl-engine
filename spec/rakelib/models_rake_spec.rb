# frozen_string_literal: true

require "spec_helper"
require "rake"

# Fact 55: `rake models:refresh` fills the models table from every catalog.
RSpec.describe "rake models:refresh" do # rubocop:disable RSpec/DescribeClass -- a rake task, not a class
  let(:db) { SFL::Store::StoreTestDb.db }
  let(:rake) { Rake::Application.new }
  let(:task) { rake["models:refresh"] }

  def entry(provider, model_id)
    SFL::Core::Ports::ModelCatalog::Entry.new(provider:, model_id:, name: model_id, context_window: nil,
      capabilities: ["chat"], pricing: {})
  end

  def catalog(name, *entries, error: nil)
    SFL::Core::Ports::Fake::ModelCatalog.new(name:, entries:, error:, providers: [(name == "ruby_llm") ? "openai" : name])
  end

  def stub_catalogs(*catalogs)
    allow(SFL::Boot).to receive(:model_catalogs).with(load_dotenv: false).and_return(catalogs)
  end

  before do
    SFL::Store::StoreTestDb.clean!
    Rake.application = rake
    load File.expand_path("../../rakelib/models.rake", __dir__)
    allow(SFL::Boot).to receive(:call).with(require_llm: false, require_tracing: false)
      .and_return(SFL::Boot::Result.new(db:))
    allow(SFL::Boot).to receive(:logger).with(load_dotenv: false).and_return(SFL::Core::Ports::Null::Logger.new)
  end

  after { Rake.application = Rake::Application.new }

  it "fills the table from the ruby_llm registry and the Ollama and OpenRouter listings" do
    stub_catalogs(catalog("ruby_llm", entry("openai", "gpt")), catalog("ollama", entry("ollama", "llama")),
      catalog("openrouter", entry("openrouter", "a/b")))

    expect { task.invoke }.to output(<<~OUT).to_stdout
      ruby_llm: 1 listed, 0 unavailable
      ollama: 1 listed, 0 unavailable
      openrouter: 1 listed, 0 unavailable
    OUT
    expect(db[:models].select_map(%i[provider model_id])).to contain_exactly(%w[openai gpt], %w[ollama llama], %w[openrouter a/b])
  end

  it "keeps a failed provider's rows, syncs the others, and aborts naming the failures" do
    db[:models].insert(provider: "openrouter", model_id: "kept")
    stub_catalogs(catalog("ollama", entry("ollama", "llama")), catalog("openrouter", error: SocketError.new("down")))

    expect { task.invoke }.to raise_error(SystemExit)
      .and output(/openrouter: failed \(SocketError: down\)/).to_stdout
      .and output(/1 of 2 catalogs failed/).to_stderr
    expect(db[:models].select_map(%i[model_id available])).to contain_exactly(["kept", true], ["llama", true])
  end
end
