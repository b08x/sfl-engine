# frozen_string_literal: true

require "spec_helper"
require "ruby_llm"

RSpec.describe SFL::LLM::Annotators::ClauseAnnotator do
  subject(:annotator) { described_class.new(chat: fake_chat) }

  let(:fake_response) { instance_double(RubyLLM::Message, content: { "mood" => "declarative" }) }
  let(:fake_chat) { instance_double(RubyLLM::Chat) }

  let(:context) do
    {
      text: "It works.",
      root_verb: "works",
      process_type: "material",
      participants: "It: Actor",
      pos_tags: "It/PRP works/VBZ",
      dependencies: "It<nsubj works<ROOT",
      semantic_coherence_score: nil,
    }
  end

  it "renders the context Hash straight into the prompt (no string round trip to re-parse)" do
    allow(fake_chat).to receive_messages(with_schema: fake_chat, ask: fake_response)

    annotator.call(context)

    expect(fake_chat).to have_received(:with_schema).with(SFL::LLM::Schemas::ClauseAnnotationSchema)
    expect(fake_chat).to have_received(:ask) do |prompt|
      expect(prompt).to include("Text: It works.")
      expect(prompt).to include("Root verb: works")
    end
  end

  it "symbolizes the response content's keys" do
    allow(fake_chat).to receive_messages(with_schema: fake_chat, ask: fake_response)

    expect(annotator.call(context)).to eq(mood: "declarative")
  end
end
