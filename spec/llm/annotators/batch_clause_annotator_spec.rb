# frozen_string_literal: true

require "spec_helper"
require "ruby_llm"

RSpec.describe SFL::LLM::Annotators::BatchClauseAnnotator do
  subject(:annotator) { described_class.new(chat: fake_chat) }

  let(:fake_response) do
    instance_double(RubyLLM::Message, content: { "annotations" => [{ "index" => 0, "mood" => "declarative" }] })
  end
  let(:fake_chat) { instance_double(RubyLLM::Chat) }

  let(:contexts) do
    [
{
  index: 0,
  text: "It works.",
  root_verb: "works",
  process_type: "material",
  participants: "It: Actor",
  pos_tags: "x",
  dependencies: "y",
},
]
  end

  it "renders every clause's context Hash into the batch prompt" do
    allow(fake_chat).to receive_messages(with_schema: fake_chat, ask: fake_response)

    annotator.call(contexts)

    expect(fake_chat).to have_received(:with_schema).with(SFL::LLM::Schemas::BatchClauseAnnotationSchema)
    expect(fake_chat).to have_received(:ask) do |prompt|
      expect(prompt).to include("### Clause 0")
      expect(prompt).to include("Text: It works.")
    end
  end

  it "returns the symbolized annotations array" do
    allow(fake_chat).to receive_messages(with_schema: fake_chat, ask: fake_response)

    expect(annotator.call(contexts)).to eq([{ index: 0, mood: "declarative" }])
  end
end
