# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::LLM::TaskConfig do
  it "requires a model" do
    expect { described_class.new }.to raise_error(Dry::Struct::Error)
  end

  it "defaults provider to nil and params to an empty Hash" do
    task_config = described_class.new(model: "gpt-4o-mini")

    expect(task_config.provider).to be_nil
    expect(task_config.params).to eq({})
  end

  it "accepts an explicit provider and params" do
    task_config = described_class.new(model: "claude-sonnet-5", provider: :anthropic, params: { temperature: 0.2 })

    expect(task_config.provider).to eq(:anthropic)
    expect(task_config.params).to eq({ temperature: 0.2 })
  end
end
