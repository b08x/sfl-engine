# frozen_string_literal: true

require "spec_helper"
require "dspy"

RSpec.describe SFL::LLM::Classifier do
  subject(:classifier) { described_class.new(lm: fake_lm) }

  let(:fake_lm) { instance_double(DSPy::LM) }
  let(:fake_predictor) { instance_double(DSPy::Predict) }

  before do
    allow(DSPy::Predict).to receive(:new).with(SFL::LLM::Signatures::ClassificationSignature).and_return(fake_predictor)
    allow(fake_predictor).to receive(:configure)
  end

  describe "#classify" do
    it "returns a ClassificationResult built from the LLM's structured response" do
      fake_response = double("Result", to_h: {
        format: "generic_jsonl_chat",
        mode: nil,
        confidence: 0.2,
        reasoning: "JSONL rows resembling a chat log, but no loader recognizes this shape"
      })
      allow(fake_predictor).to receive(:call).and_return(fake_response)

      result = classifier.classify("path: weird_chat.jsonl\n...", "weird_chat.jsonl")

      expect(fake_predictor).to have_received(:call) do |**args|
        expect(args[:path]).to eq("weird_chat.jsonl")
      end
      expect(result).to be_a(SFL::Core::Types::ClassificationResult)
      expect(result.format).to eq("generic_jsonl_chat")
      expect(result.mode).to be_nil
      expect(result.confidence).to eq(0.2)
      expect(result.reasoning).to include("JSONL rows")
    end

    it "returns a low-confidence unknown result, not a raised error, when the LLM call fails" do
      allow(fake_predictor).to receive(:call).and_raise(SFL::LLM::Error, "rate limited")

      result = classifier.classify("some sample", "some/path.txt")

      expect(result).to be_a(SFL::Core::Types::ClassificationResult)
      expect(result.format).to eq("unknown")
      expect(result.mode).to be_nil
      expect(result.confidence).to eq(0.0)
      expect(result.reasoning).to include("rate limited")
    end

    it "returns a low-confidence unknown result, not a raised error, when the LLM's response " \
      "violates ClassificationResult's own contract (e.g. an out-of-range confidence) — matching " \
      "LLM::Engine#annotate's identical degrade-on-any-failure boundary" do
      fake_response = double("Result", to_h: {
        format: "markdown", mode: "documentation", confidence: 1.5, reasoning: "r"
      })
      allow(fake_predictor).to receive(:call).and_return(fake_response)

      result = classifier.classify("some sample", "some/path.txt")

      expect(result.format).to eq("unknown")
      expect(result.confidence).to eq(0.0)
      expect(result.reasoning).to include("confidence")
    end
  end
end
