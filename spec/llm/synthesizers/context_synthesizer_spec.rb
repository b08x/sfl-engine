# frozen_string_literal: true

require "spec_helper"
require "ruby_llm"

RSpec.describe SFL::LLM::Synthesizers::ContextSynthesizer do
  subject(:synthesizer) { described_class.new(chat: fake_chat) }

  let(:fake_response) do
    instance_double(
      RubyLLM::Message,
      content: { "answer" => "It works.", "cited_clause_numbers" => [1], "confidence" => 0.9 }
    )
  end
  let(:fake_chat) { instance_double(RubyLLM::Chat) }

  it "renders the query/evidence into the prompt via the context_synthesis template" do
    allow(fake_chat).to receive_messages(with_schema: fake_chat, ask: fake_response)

    synthesizer.call(query: "Does it work?", evidence: "[1] It works.\n    (mood=declarative; source: doc-1)")

    expect(fake_chat).to have_received(:with_schema).with(SFL::LLM::Schemas::SynthesisSchema)
    expect(fake_chat).to have_received(:ask) do |prompt|
      expect(prompt).to include("Query: Does it work?")
      expect(prompt).to include("[1] It works.")
    end
  end

  it "symbolizes the response content's keys" do
    allow(fake_chat).to receive_messages(with_schema: fake_chat, ask: fake_response)

    result = synthesizer.call(query: "Does it work?", evidence: "[1] It works.")

    expect(result).to eq(answer: "It works.", cited_clause_numbers: [1], confidence: 0.9)
  end
end
