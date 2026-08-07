# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Types::ClassificationResult do
  it "builds from format/mode/confidence/reasoning" do
    result = described_class.new(
      format: "markdown_chat", mode: "conversation", confidence: 0.4,
      reasoning: "Has speaker-labeled lines but also prose paragraphs"
    )

    expect(result.format).to eq("markdown_chat")
    expect(result.mode).to eq("conversation")
    expect(result.confidence).to eq(0.4)
  end

  it "allows a nil mode (format recognized, mode undetermined)" do
    result = described_class.new(
      format: "unknown", mode: nil, confidence: 0.2, reasoning: "no loader recognizes this shape"
    )

    expect(result.mode).to be_nil
  end

  it "coerces an Integer confidence to Float (LLM-boundary coercion, same rationale as " \
    "ReasoningTrace#confidence)" do
    result = described_class.new(format: "markdown", mode: "documentation", confidence: 1, reasoning: "r")

    expect(result.confidence).to eq(1.0)
  end

  it "rejects a confidence outside 0.0..1.0" do
    expect do
      described_class.new(format: "markdown", mode: "documentation", confidence: 1.5, reasoning: "r")
    end.to raise_error(Dry::Struct::Error)
  end
end
