# frozen_string_literal: true

require "spec_helper"
require "ruby_llm"

RSpec.describe SFL::LLM::Classifier do
  subject(:classifier) { described_class.new(chat: fake_chat) }

  let(:fake_chat) { instance_double(RubyLLM::Chat) }

  describe "#classify" do
    it "returns a ClassificationResult built from the LLM's structured response" do
      fake_response = instance_double(RubyLLM::Message, content: {
        "format" => "generic_jsonl_chat",
        "mode" => nil,
        "confidence" => 0.2,
        "reasoning" => "JSONL rows resembling a chat log, but no loader recognizes this shape",
      })
      allow(fake_chat).to receive_messages(with_schema: fake_chat, ask: fake_response)

      result = classifier.classify("path: weird_chat.jsonl\n...", "weird_chat.jsonl")

      expect(fake_chat).to have_received(:with_schema).with(SFL::LLM::Schemas::ClassificationSchema)
      expect(fake_chat).to have_received(:ask) do |prompt|
        expect(prompt).to include("weird_chat.jsonl")
      end
      expect(result).to be_a(SFL::Core::Types::ClassificationResult)
      expect(result.format).to eq("generic_jsonl_chat")
      expect(result.mode).to be_nil
      expect(result.confidence).to eq(0.2)
      expect(result.reasoning).to include("JSONL rows")
    end

    it "returns a low-confidence unknown result, not a raised error, when the LLM call fails" do
      allow(fake_chat).to receive(:with_schema).and_return(fake_chat)
      allow(fake_chat).to receive(:ask).and_raise(RubyLLM::Error, "rate limited")

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
      fake_response = instance_double(RubyLLM::Message, content: {
        "format" => "markdown", "mode" => "documentation", "confidence" => 1.5, "reasoning" => "r"
      })
      allow(fake_chat).to receive_messages(with_schema: fake_chat, ask: fake_response)

      result = classifier.classify("some sample", "some/path.txt")

      expect(result.format).to eq("unknown")
      expect(result.confidence).to eq(0.0)
      expect(result.reasoning).to include("confidence")
    end
  end
end
