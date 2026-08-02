# frozen_string_literal: true

require "spec_helper"
require "ruby_llm"

RSpec.describe SFL::LLM::Embedder do
  # Never touch the real ::RubyLLM module (house rule: no real LLM/embedding
  # network calls in specs) — Embedder takes `ruby_llm:` as an injectable
  # seam precisely so specs can pass a plain double here instead of the
  # real global, for both RubyLLM.configure (called once at initialize)
  # and RubyLLM.embed (called on #embed/#embed_batch).
  subject(:embedder) do
    described_class.new(model: "embeddinggemma:latest", ollama_base_url: "http://tinybot:11434", ruby_llm:)
  end

  # rubocop:disable RSpec/VerifiedDoubles -- deliberately plain doubles, not verified against
  # ::RubyLLM/::RubyLLM::Configuration: a verifying double would have to reference the real
  # constants, which is exactly the global touch this spec exists to avoid (see comment above).
  # `ruby_llm:` is a duck-typed injectable seam (#configure/#embed), not a stand-in for a
  # specific class.
  let(:ruby_llm_config) { double("ruby_llm_config", "ollama_api_base=": nil, "default_embedding_model=": nil) }
  let(:ruby_llm) { double("ruby_llm") }
  # rubocop:enable RSpec/VerifiedDoubles

  before do
    allow(ruby_llm).to receive(:configure).and_yield(ruby_llm_config)
  end

  describe "#initialize" do
    it "configures RubyLLM with an OpenAI-compatible (/v1-suffixed) Ollama base URL and the default embedding model" do
      embedder

      expect(ruby_llm_config).to have_received(:ollama_api_base=).with("http://tinybot:11434/v1")
      expect(ruby_llm_config).to have_received(:default_embedding_model=).with("embeddinggemma:latest")
    end

    it "does not double up the /v1 suffix when the base URL already has one" do
      described_class.new(model: "m", ollama_base_url: "http://tinybot:11434/v1", ruby_llm:)

      expect(ruby_llm_config).to have_received(:ollama_api_base=).with("http://tinybot:11434/v1")
    end

    it "still configures ollama_api_base globally even when provider: is not :ollama " \
      "(a later ollama-provider call, chat or embedding, needs it available)" do
      described_class.new(model: "mistral-embed", provider: :mistral, ollama_base_url: "http://tinybot:11434",
        ruby_llm:)

      expect(ruby_llm_config).to have_received(:ollama_api_base=).with("http://tinybot:11434/v1")
    end
  end

  describe "#embed" do
    it "returns the vector RubyLLM.embed produces" do
      response = instance_double(RubyLLM::Embedding, vectors: [0.1, 0.2, 0.3])
      allow(ruby_llm).to receive(:embed).with("hello", model: "embeddinggemma:latest", provider: :ollama)
        .and_return(response)

      expect(embedder.embed("hello")).to eq([0.1, 0.2, 0.3])
    end

    it "forwards a non-default provider: (e.g. :mistral) to RubyLLM.embed instead of hardcoding :ollama" do
      mistral_embedder = described_class.new(model: "mistral-embed", provider: :mistral,
        ollama_base_url: "http://tinybot:11434", ruby_llm:)
      response = instance_double(RubyLLM::Embedding, vectors: [0.4, 0.5])
      allow(ruby_llm).to receive(:embed).with("hi", model: "mistral-embed", provider: :mistral).and_return(response)

      expect(mistral_embedder.embed("hi")).to eq([0.4, 0.5])
    end

    it "raises ArgumentError for nil text without calling RubyLLM" do
      allow(ruby_llm).to receive(:embed)

      expect { embedder.embed(nil) }.to raise_error(ArgumentError)
      expect(ruby_llm).not_to have_received(:embed)
    end

    it "raises ArgumentError for blank text without calling RubyLLM" do
      allow(ruby_llm).to receive(:embed)

      expect { embedder.embed("   ") }.to raise_error(ArgumentError)
      expect(ruby_llm).not_to have_received(:embed)
    end

    it "raises SFL::LLM::Error (never returns nil) when RubyLLM.embed fails" do
      allow(ruby_llm).to receive(:embed).and_raise(StandardError, "connection refused")

      expect { embedder.embed("hello") }.to raise_error(SFL::LLM::Error, /connection refused/)
    end

    it "raises SFL::LLM::Error when the breaker is open" do
      breaker = instance_double(SFL::Core::Ports::Breaker)
      allow(breaker).to receive(:call).and_raise(SFL::Core::Ports::Breaker::OpenError, "open")
      open_embedder = described_class.new(model: "m", ollama_base_url: "http://tinybot:11434", breaker:, ruby_llm:)

      expect { open_embedder.embed("hello") }.to raise_error(SFL::LLM::Error, /open/)
    end
  end

  describe "#embed_batch" do
    it "returns [] for an empty input without calling RubyLLM" do
      allow(ruby_llm).to receive(:embed)

      expect(embedder.embed_batch([])).to eq([])
      expect(ruby_llm).not_to have_received(:embed)
    end

    it "returns one vector per input text, in order" do
      response = instance_double(RubyLLM::Embedding, vectors: [[0.1, 0.2], [0.3, 0.4]])
      allow(ruby_llm).to receive(:embed).with(%w[a b], model: "embeddinggemma:latest", provider: :ollama)
        .and_return(response)

      expect(embedder.embed_batch(%w[a b])).to eq([[0.1, 0.2], [0.3, 0.4]])
    end

    it "raises SFL::LLM::Error (never returns nil) when RubyLLM.embed fails" do
      allow(ruby_llm).to receive(:embed).and_raise(StandardError, "timeout")

      expect { embedder.embed_batch(%w[a b]) }.to raise_error(SFL::LLM::Error, /timeout/)
    end
  end
end
