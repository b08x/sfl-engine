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

  describe ".install! with an Anthropic client" do
    # Mirrors DSPy::Anthropic AnthropicAdapter -> @client (Anthropic::Client) -> messages.
    let(:messages) do
      Class.new do
        attr_reader :sent, :streamed

        def create(params)
          @sent = params
          :response
        end

        def stream(params)
          @streamed = params
          :stream
        end
      end.new
    end
    let(:anthropic_lm) do
      client = Struct.new(:messages).new(messages)
      adapter = Object.new.tap { |a| a.instance_variable_set(:@client, client) }
      Struct.new(:adapter).new(adapter)
    end

    it "removes the adapter's temperature from create when the task omits it" do
      described_class.install!(anthropic_lm, params: { omit_temperature: true }, openrouter: false)

      result = messages.create(model: "claude-opus-5-5", max_tokens: 4096, messages: [], temperature: 0.0)

      expect(result).to eq(:response)
      expect(messages.sent).to eq(model: "claude-opus-5-5", max_tokens: 4096, messages: [])
    end

    it "removes the adapter's temperature from stream as well, so the streaming path is covered" do
      described_class.install!(anthropic_lm, params: { omit_temperature: true }, openrouter: false)

      expect(messages.stream(model: "claude-opus-5-5", max_tokens: 4096, temperature: 0.0)).to eq(:stream)
      expect(messages.streamed).not_to have_key(:temperature)
    end

    it "does not raise when temperature is omitted, the case that used to fail on the chat.completions check" do
      expect { described_class.install!(anthropic_lm, params: { omit_temperature: true }, openrouter: false) }
        .not_to raise_error
    end

    it "sends the configured temperature and max_tokens in place of the adapter's values" do
      described_class.install!(anthropic_lm, params: { temperature: 0.2, max_tokens: 1024 }, openrouter: false)

      messages.create(model: "claude-sonnet-4-6", max_tokens: 4096, messages: [], temperature: 0.0)

      expect(messages.sent).to include(temperature: 0.2, max_tokens: 1024)
    end

    it "returns the lm it was given" do
      expect(described_class.install!(anthropic_lm, params: { omit_temperature: true }, openrouter: false))
        .to be(anthropic_lm)
    end

    it "raises when a seed is configured, since the Messages API takes none" do
      expect { described_class.install!(anthropic_lm, params: { seed: 3 }, openrouter: false) }
        .to raise_error(SFL::LLM::RequestPinning::Error, /seed/)
    end

    it "raises when a reasoning effort is configured, since it is not pinned on Anthropic" do
      expect { described_class.install!(anthropic_lm, params: { reasoning_effort: "low" }, openrouter: false) }
        .to raise_error(SFL::LLM::RequestPinning::Error, /reasoning_effort/)
    end
  end

  describe ".install! for provider anthropic with the model named" do
    let(:messages) do
      Class.new do
        attr_reader :sent

        def create(params)
          @sent = params
          :response
        end

        def stream(params)
          @streamed = params
          :stream
        end
      end.new
    end
    let(:anthropic_lm) do
      client = Struct.new(:messages).new(messages)
      adapter = Object.new.tap { |a| a.instance_variable_set(:@client, client) }
      Struct.new(:adapter).new(adapter)
    end

    def install_anthropic(params:, model:)
      described_class.install!(anthropic_lm, params:, openrouter: false, provider: "anthropic", model:)
    end

    it "omits temperature by default when the task sets none, so the adapter's 0.0 is not sent" do
      install_anthropic(params: {}, model: "claude-opus-4-6")

      messages.create(model: "claude-opus-4-6", max_tokens: 4096, messages: [], temperature: 0.0)

      expect(messages.sent).not_to have_key(:temperature)
    end

    it "keeps max_tokens while omitting the default temperature" do
      install_anthropic(params: { max_tokens: 1024 }, model: "claude-opus-4-6")

      messages.create(model: "claude-opus-4-6", max_tokens: 4096, messages: [], temperature: 0.0)

      expect(messages.sent).to include(max_tokens: 1024)
      expect(messages.sent).not_to have_key(:temperature)
    end

    it "rejects a numeric temperature on a fixed-sampling model, naming the model and saying to set none" do
      expect { install_anthropic(params: { temperature: 0.2 }, model: "claude-sonnet-5-20260315") }
        .to raise_error(SFL::LLM::RequestPinning::Error, /claude-sonnet-5-20260315.*set this task's temperature to none/)
    end

    it "allows a numeric temperature on a model whose capability is not fixed-sampling" do
      install_anthropic(params: { temperature: 0.2 }, model: "claude-opus-4-6")

      messages.create(model: "claude-opus-4-6", max_tokens: 4096, messages: [], temperature: 0.0)

      expect(messages.sent).to include(temperature: 0.2)
    end

    it "allows a numeric temperature on a model the capability table does not list" do
      expect { install_anthropic(params: { temperature: 0.2 }, model: "claude-unlisted-9") }.not_to raise_error
    end

    it "does not raise on a fixed-sampling model when the temperature is none" do
      expect { install_anthropic(params: { omit_temperature: true }, model: "claude-sonnet-5-20260315") }
        .not_to raise_error

      messages.create(model: "claude-sonnet-5-20260315", max_tokens: 4096, messages: [], temperature: 0.0)

      expect(messages.sent).not_to have_key(:temperature)
    end

    it "does not raise on a fixed-sampling model when no temperature is configured" do
      expect { install_anthropic(params: {}, model: "claude-sonnet-5-20260315") }.not_to raise_error
    end

    it "leaves the params hash the caller passed unchanged" do
      params = {}

      install_anthropic(params:, model: "claude-opus-4-6")

      expect(params).to eq({})
    end
  end

  describe ".install! with an Anthropic response that carries no answer" do
    # Mirrors the SDK Message shape: stop_reason is a Symbol, content is a list of typed blocks.
    let(:block_class) { Struct.new(:type, :text) }
    let(:message_class) { Struct.new(:stop_reason, :content) }

    let(:messages) do
      Class.new do
        attr_accessor :response

        def create(_params)
          response
        end

        def stream(_params)
          :stream
        end
      end.new
    end
    let(:anthropic_lm) do
      client = Struct.new(:messages).new(messages)
      adapter = Object.new.tap { |a| a.instance_variable_set(:@client, client) }
      Struct.new(:adapter).new(adapter)
    end

    before { described_class.install!(anthropic_lm, params: { omit_temperature: true }, openrouter: false) }

    it "raises a named error when the response stops with stop_reason refusal, even with text present" do
      messages.response = message_class.new(:refusal, [block_class.new("thinking", nil), block_class.new("text", "{\"a")])

      expect { messages.create(model: "claude-opus-5-5", max_tokens: 4096, messages: []) }
        .to raise_error(described_class::Error, /stop_reason refusal.*block types thinking, text/)
    end

    it "raises a named error when a thinking-only response has no text block" do
      messages.response = message_class.new(:max_tokens, [block_class.new("thinking", nil)])

      expect { messages.create(model: "claude-opus-5-5", max_tokens: 4096, messages: []) }
        .to raise_error(described_class::Error, /no text block \(stop_reason max_tokens, block types thinking\)/)
    end

    it "returns a response that carries a text block unchanged" do
      response = message_class.new(:end_turn, [block_class.new("text", "{}")])
      messages.response = response

      expect(messages.create(model: "claude-opus-5-5", max_tokens: 4096, messages: [])).to be(response)
    end

    it "returns a tool_use-only response unchanged, since it carries no text by design" do
      response = message_class.new(:tool_use, [block_class.new("tool_use", nil)])
      messages.response = response

      expect(messages.create(model: "claude-opus-5-5", max_tokens: 4096, messages: [])).to be(response)
    end

    it "does not check the stream response" do
      expect(messages.stream(model: "claude-opus-5-5", max_tokens: 4096, messages: [])).to eq(:stream)
    end
  end

  describe ".apply_anthropic" do
    it "drops temperature when omitted and leaves the input unchanged" do
      request = { model: "claude-opus-5-5", temperature: 0.0 }

      pinned = described_class.apply_anthropic(request, params: { omit_temperature: true })

      expect(pinned).to eq(model: "claude-opus-5-5")
      expect(request).to eq(model: "claude-opus-5-5", temperature: 0.0)
    end

    it "adds no OpenRouter request_options" do
      pinned = described_class.apply_anthropic({ model: "claude-sonnet-4-6" }, params: { temperature: 0.1 })

      expect(pinned).to eq(model: "claude-sonnet-4-6", temperature: 0.1)
    end
  end
end
