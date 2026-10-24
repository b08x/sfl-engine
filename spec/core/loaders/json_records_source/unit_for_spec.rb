# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::JsonRecordsSource::UnitFor do
  let(:record) { { "uuid" => "c-alpha", "name" => "Chat" } }

  def build(message, number: 0)
    described_class.call(record:, number:, text: "hello", message:, path: "/tmp/a.json")
  end

  it "builds a unit keyed by the conversation uuid with the turn number" do
    unit = build({ "sender" => "human" }, number: 3)

    expect(unit).to have_attributes(section_id: "c-alpha#turn-3", document_key: "c-alpha", text: "hello", source_path: "/tmp/a.json")
  end

  it "marks a human sender as the user" do
    expect(build({ "sender" => "human" })).to have_attributes(is_user: true, speaker: "Human")
  end

  it "marks any other sender as the assistant" do
    expect(build({ "sender" => "assistant" })).to have_attributes(is_user: false, speaker: "Assistant")
  end

  it "parses created_at and leaves an unparseable value nil" do
    expect(build({ "created_at" => "2024-06-15T18:35:00Z" }).sent_at).to eq(Time.utc(2024, 6, 15, 18, 35, 0))
    expect(build({ "created_at" => "not a date" }).sent_at).to be_nil
  end

  it "keeps the conversation name in metadata unchanged" do
    expect(build({}).metadata).to eq("conversation_id" => "c-alpha", "conversation_title" => "Chat")
  end
end
