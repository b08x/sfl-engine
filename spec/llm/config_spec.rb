# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::LLM::Config do
  subject(:config) { described_class.new(tasks: { pass_two_annotation: pass_two_task }) }

  let(:pass_two_task) { SFL::LLM::TaskConfig.new(model: "gpt-4o-mini") }

  describe "#for" do
    it "returns the TaskConfig registered for a known task" do
      expect(config.for(:pass_two_annotation)).to eq(pass_two_task)
    end

    it "raises SFL::LLM::Error for an unregistered task" do
      expect { config.for(:topic_labeling) }.to raise_error(SFL::LLM::Error, /topic_labeling/)
    end
  end
end
