# frozen_string_literal: true

require "spec_helper"
require "ruby_llm"

RSpec.describe SFL::LLM::EngineBuilder do
  let(:single_chat) { instance_double(RubyLLM::Chat) }
  let(:batch_chat) { instance_double(RubyLLM::Chat) }

  let(:config) do
    SFL::LLM::Config.new(tasks: {
      pass_two_annotation: SFL::LLM::TaskConfig.new(model: "gpt-4o-mini"),
      pass_two_batch_annotation: SFL::LLM::TaskConfig.new(model: "gpt-4o"),
    })
  end

  let(:chat_factory) { instance_double(SFL::LLM::ChatFactory) }

  before do
    allow(chat_factory).to receive(:for).with(:pass_two_annotation).and_return(single_chat)
    allow(chat_factory).to receive(:for).with(:pass_two_batch_annotation).and_return(batch_chat)
  end

  it "resolves the single-clause task and the batch task to their own independently-configured chats" do
    described_class.call(config:, chat_factory:)

    expect(chat_factory).to have_received(:for).with(:pass_two_annotation)
    expect(chat_factory).to have_received(:for).with(:pass_two_batch_annotation)
  end

  it "returns an SFL::LLM::Engine" do
    expect(described_class.call(config:, chat_factory:)).to be_a(SFL::LLM::Engine)
  end
end
