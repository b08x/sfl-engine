# frozen_string_literal: true

require "spec_helper"
require "ruby_llm"

RSpec.describe SFL::LLM::ChatFactory do
  subject(:chat_factory) { described_class.new(config:, chat_builder:) }

  let(:chat) { instance_double(RubyLLM::Chat) }
  let(:chat_builder) { instance_double(Proc, call: chat) }

  let(:config) do
    SFL::LLM::Config.new(tasks: {
      pass_two_annotation: SFL::LLM::TaskConfig.new(model: "gpt-4o-mini", provider: :openai),
    })
  end

  it "builds a chat from the task's model and provider" do
    chat_factory.for(:pass_two_annotation)

    expect(chat_builder).to have_received(:call).with(model: "gpt-4o-mini", provider: :openai)
  end

  it "returns the built chat unchanged when the task has no params" do
    expect(chat_factory.for(:pass_two_annotation)).to eq(chat)
  end

  context "with a temperature param" do
    let(:config) do
      SFL::LLM::Config.new(tasks: {
        pass_two_annotation: SFL::LLM::TaskConfig.new(model: "gpt-4o-mini", params: { temperature: 0.2 }),
      })
    end

    it "applies it via #with_temperature" do
      allow(chat).to receive(:with_temperature).with(0.2).and_return(chat)

      chat_factory.for(:pass_two_annotation)

      expect(chat).to have_received(:with_temperature).with(0.2)
    end
  end

  context "with non-temperature params" do
    let(:config) do
      SFL::LLM::Config.new(tasks: {
        pass_two_annotation: SFL::LLM::TaskConfig.new(model: "gpt-4o-mini", params: { max_tokens: 500 }),
      })
    end

    it "passes them through #with_params" do
      allow(chat).to receive(:with_params).with(max_tokens: 500).and_return(chat)

      chat_factory.for(:pass_two_annotation)

      expect(chat).to have_received(:with_params).with(max_tokens: 500)
    end
  end
end
