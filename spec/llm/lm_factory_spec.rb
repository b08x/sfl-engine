# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::LLM::LMFactory do
  let(:config) { Struct.new(:task_config) { def for(_task) = task_config }.new(task_config) }
  let(:env) { { "OPENROUTER_API_KEY" => "or-test-key" } }
  let(:factory) { described_class.new(config:, env:) }

  context "with an OpenRouter task that pins temperature and seed" do
    let(:task_config) do
      SFL::LLM::TaskConfig.new(model: "qwen/qwen3.5-flash-02-23", provider: :openrouter,
        params: { temperature: 0.0, seed: 1 })
    end

    it "does not pass temperature to DSPy::LM.new, where the adapter would ignore it" do
      allow(DSPy::LM).to receive(:new).and_call_original

      factory.for(:pass_two_annotation)

      expect(DSPy::LM).to have_received(:new).with("openrouter/qwen/qwen3.5-flash-02-23", api_key: "or-test-key")
    end

    it "installs the request pinning on the adapter's completions object" do
      lm = factory.for(:pass_two_annotation)
      completions = lm.adapter.instance_variable_get(:@client).chat.completions

      expect(completions.singleton_methods).to include(:create)
    end
  end

  context "with an OpenRouter task that sets no knobs" do
    let(:task_config) { SFL::LLM::TaskConfig.new(model: "qwen/qwen3.5-flash-02-23", provider: :openrouter) }

    it "still installs the pinning, so require_parameters is sent on every request" do
      lm = factory.for(:pass_two_annotation)
      completions = lm.adapter.instance_variable_get(:@client).chat.completions

      expect(completions.singleton_methods).to include(:create)
    end
  end

  context "with an Anthropic task that omits temperature (SFL_TASK_*_TEMPERATURE=none)" do
    let(:env) { { "ANTHROPIC_API_KEY" => "ant-test-key" } }
    let(:task_config) do
      SFL::LLM::TaskConfig.new(model: "claude-opus-5-5", provider: :anthropic, params: { omit_temperature: true })
    end

    it "builds the LM without raising and pins the Anthropic messages create and stream calls" do
      lm = nil
      expect { lm = factory.for(:narrative_generation) }.not_to raise_error

      messages = lm.adapter.instance_variable_get(:@client).messages
      expect(messages.singleton_methods).to include(:create, :stream)
    end
  end

  context "with an Anthropic task that sets a numeric temperature on a fixed-sampling model" do
    let(:env) { { "ANTHROPIC_API_KEY" => "ant-test-key" } }
    let(:task_config) do
      SFL::LLM::TaskConfig.new(model: "claude-sonnet-5-20260315", provider: :anthropic, params: { temperature: 0.2 })
    end

    it "rejects the configuration at install, before any request is sent" do
      expect { factory.for(:narrative_generation) }
        .to raise_error(SFL::LLM::RequestPinning::Error, /claude-sonnet-5-20260315/)
    end
  end

  context "with an Anthropic task that sets no temperature" do
    let(:env) { { "ANTHROPIC_API_KEY" => "ant-test-key" } }
    let(:task_config) { SFL::LLM::TaskConfig.new(model: "claude-opus-5-5", provider: :anthropic) }

    it "pins the Anthropic create call so the adapter's default temperature is omitted" do
      lm = factory.for(:narrative_generation)

      messages = lm.adapter.instance_variable_get(:@client).messages
      expect(messages.singleton_methods).to include(:create, :stream)
    end
  end

  describe "#credentials_for" do
    context "with a provider the key mapping does not cover" do
      let(:task_config) { SFL::LLM::TaskConfig.new(model: "test-model", provider: :test_provider) }

      it "returns the provider as a String, the model, and a nil api key, without raising" do
        expect(factory.credentials_for(:narrative_generation))
          .to eq(provider: "test_provider", model: "test-model", api_key: nil, api_base: nil)
      end

      it "builds no DSPy object" do
        allow(DSPy::LM).to receive(:new)

        factory.credentials_for(:narrative_generation)

        expect(DSPy::LM).not_to have_received(:new)
      end
    end

    # The key mapping is provider-specific by nature; this reuses the
    # provider name and env fixture the #for examples above already use.
    context "with a provider the key mapping covers" do
      let(:task_config) { SFL::LLM::TaskConfig.new(model: "test-model", provider: :openrouter) }

      it "returns the key #for would pass to DSPy::LM.new" do
        expect(factory.credentials_for(:narrative_generation))
          .to eq(provider: "openrouter", model: "test-model", api_key: "or-test-key", api_base: nil)
      end
    end

    # RubyLLM's Ollama provider needs an API base; the DSPy path fell back to
    # a default host, so this does too.
    context "with the ollama provider" do
      let(:task_config) { SFL::LLM::TaskConfig.new(model: "test-model", provider: :ollama) }

      it "uses OLLAMA_BASE_URL from the injected env, as the /v1 route RubyLLM posts under" do
        factory = described_class.new(config:, env: { "OLLAMA_BASE_URL" => "http://ollama.test:11434/" })

        expect(factory.credentials_for(:narrative_generation))
          .to eq(provider: "ollama", model: "test-model", api_key: nil, api_base: "http://ollama.test:11434/v1")
      end

      it "keeps a base URL that already ends in /v1" do
        factory = described_class.new(config:, env: { "OLLAMA_BASE_URL" => "http://ollama.test:11434/v1" })

        expect(factory.credentials_for(:narrative_generation)[:api_base]).to eq("http://ollama.test:11434/v1")
      end

      it "falls back to Boot::DEFAULT_OLLAMA_BASE_URL when OLLAMA_BASE_URL is unset or blank" do
        [{}, { "OLLAMA_BASE_URL" => " " }].each do |env|
          factory = described_class.new(config:, env:)

          expect(factory.credentials_for(:narrative_generation)[:api_base])
            .to eq("#{SFL::Boot::DEFAULT_OLLAMA_BASE_URL}/v1")
        end
      end
    end
  end
end
