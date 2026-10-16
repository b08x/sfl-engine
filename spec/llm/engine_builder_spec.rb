# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::LLM::EngineBuilder do
  it "passes provider and model from the :pass_two_annotation task config to the Engine" do
    task = SFL::LLM::TaskConfig.new(model: "qwen3", provider: :ollama)
    config = SFL::LLM::Config.new(tasks: { pass_two_annotation: task, pass_two_batch_annotation: task })
    lm_factory = instance_double(SFL::LLM::LMFactory, for: double)
    allow(SFL::LLM::Annotators::ClauseAnnotator).to receive(:new).and_return(double)
    allow(SFL::LLM::Annotators::BatchClauseAnnotator).to receive(:new).and_return(double)
    allow(SFL::LLM::Engine).to receive(:new).and_call_original

    described_class.call(config:, lm_factory:)

    expect(SFL::LLM::Engine).to have_received(:new).with(hash_including(provider: :ollama, model: "qwen3"))
  end
end
