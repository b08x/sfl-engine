# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::LLM::RequestPinning do
  describe ".apply" do
    let(:pinned_task) do
      {
        temperature: 0.0, seed: 7, max_tokens: 512, reasoning_effort: "low"
      }
    end

    it "sets temperature, seed and max_tokens, and adds the OpenRouter pins, when every knob is configured" do
      request = { model: "qwen", messages: [], temperature: 1.0 }

      pinned = described_class.apply(request, params: pinned_task, openrouter: true)

      expect(pinned).to include(temperature: 0.0, seed: 7, max_tokens: 512)
      expect(pinned[:request_options]).to eq(
        extra_body: { provider: { require_parameters: true }, reasoning: { effort: "low" } }
      )
    end

    it "sends only require_parameters when no knob is configured" do
      pinned = described_class.apply({ model: "qwen", messages: [] }, params: {}, openrouter: true)

      expect(pinned.keys).to contain_exactly(:model, :messages, :request_options)
      expect(pinned[:request_options]).to eq(extra_body: { provider: { require_parameters: true } })
    end

    it "removes a hardcoded temperature when the task configures temperature as none" do
      pinned = described_class.apply({ model: "gpt-5.6-luna-pro", temperature: 1.0 },
        params: { omit_temperature: true }, openrouter: true)

      expect(pinned).not_to have_key(:temperature)
    end

    it "keeps the extra_headers the OpenRouter adapter already set, and merges the pins beside them" do
      request = { model: "qwen", request_options: { extra_headers: { "X-Title" => "sfl" } } }

      pinned = described_class.apply(request, params: { reasoning_effort: "medium" }, openrouter: true)

      expect(pinned[:request_options]).to eq(
        extra_headers: { "X-Title" => "sfl" },
        extra_body: { provider: { require_parameters: true }, reasoning: { effort: "medium" } }
      )
    end

    it "adds no OpenRouter fields for a non-OpenRouter provider" do
      pinned = described_class.apply({ model: "gpt-4o" }, params: { temperature: 0.2, seed: 1 }, openrouter: false)

      expect(pinned).to eq(model: "gpt-4o", temperature: 0.2, seed: 1)
    end

    it "does not mutate the request it was given" do
      request = { model: "qwen", temperature: 1.0 }

      described_class.apply(request, params: { temperature: 0.0 }, openrouter: true)

      expect(request).to eq(model: "qwen", temperature: 1.0)
    end
  end

  describe ".install!" do
    # Mirrors the object graph DSPy::LM -> adapter(@client) -> chat -> completions.
    let(:completions) do
      Class.new do
        attr_reader :sent

        def create(params)
          @sent = params
          :response
        end
      end.new
    end
    let(:lm) do
      client = Struct.new(:chat).new(Struct.new(:completions).new(completions))
      adapter = Object.new.tap { |a| a.instance_variable_set(:@client, client) }
      Struct.new(:adapter).new(adapter)
    end
    # An adapter whose @client doesn't expose chat.completions — what a
    # dspy-openai client-shape change would leave install! looking at.
    let(:unwrappable_lm) do
      adapter = Object.new.tap { |a| a.instance_variable_set(:@client, Object.new) }
      Struct.new(:adapter).new(adapter)
    end

    it "routes the adapter's create call through the pinned params, which win over the adapter's own values" do
      described_class.install!(lm, params: { temperature: 0.0, seed: 3 }, openrouter: true)

      result = completions.create(model: "qwen", messages: [], temperature: 1.0)

      expect(result).to eq(:response)
      expect(completions.sent).to include(model: "qwen", temperature: 0.0, seed: 3)
      expect(completions.sent[:request_options]).to eq(extra_body: { provider: { require_parameters: true } })
    end

    it "returns the lm it was given" do
      expect(described_class.install!(lm, params: {}, openrouter: false)).to be(lm)
    end

    it "raises when knobs are configured but the client shape cannot be wrapped" do
      expect { described_class.install!(unwrappable_lm, params: { temperature: 0.0 }, openrouter: false) }
        .to raise_error(SFL::LLM::RequestPinning::Error, /chat\.completions/)
    end

    it "raises when the OpenRouter provider pin must be applied but the client shape cannot be wrapped" do
      expect { described_class.install!(unwrappable_lm, params: {}, openrouter: true) }
        .to raise_error(SFL::LLM::RequestPinning::Error, /chat\.completions/)
    end

    it "returns the lm unchanged when nothing is configured to pin, even if the shape is unrecognized" do
      expect(described_class.install!(unwrappable_lm, params: {}, openrouter: false)).to be(unwrappable_lm)
    end
  end
end
