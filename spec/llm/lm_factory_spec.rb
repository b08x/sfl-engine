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
end
