# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe SFL::Core::Loaders::JsonRecordsSource do
  let(:dir) { Dir.mktmpdir }
  let(:logger) { instance_spy(SFL::Core::Ports::Logger) }

  after { FileUtils.remove_entry(dir) }

  def msg(text, sender: "human", **extra) = { "sender" => sender, "text" => text, "created_at" => "2024-06-15T18:35:00Z" }.merge(extra)
  def convo(uuid, *messages, **extra) = { "uuid" => uuid, "name" => "Chat", "chat_messages" => messages }.merge(extra)

  def write(name, content)
    path = File.join(dir, name)
    File.write(path, content.is_a?(String) ? content : JSON.generate(content))
    path
  end

  def units_for(content, name: "conversations.json")
    path = write(name, content)
    described_class.new(file_ref(path), logger:).each_unit.to_a
  end

  it "yields one unit per message, keyed by the conversation uuid, with turn numbers from 0" do
    units = units_for([convo("c-alpha", msg("first"), msg("second", sender: "assistant")), convo("c-beta", msg("fourth"))])

    expect(units.map(&:section_id)).to eq(%w[c-alpha#turn-0 c-alpha#turn-1 c-beta#turn-0])
    expect(units.map(&:document_key)).to eq(%w[c-alpha c-alpha c-beta])
    expect(units.map(&:is_user)).to eq([true, false, true])
    expect(units.map(&:speaker)).to eq(%w[Human Assistant Human])
    expect(units.first.metadata).to include("conversation_id" => "c-alpha", "conversation_title" => "Chat")
    expect(logger).not_to have_received(:warn)
  end

  it "takes the text from the text field only" do
    units = units_for([convo("c-alpha", { "text" => "from text", "content" => [{ "type" => "text", "text" => "from content" }] })])

    expect(units.map(&:text)).to eq(["from text"])
  end

  it "skips a message with blank text without using a turn number" do
    units = units_for([convo("c-alpha", msg("one"), msg("  "), msg("three"))])

    expect(units.map(&:section_id)).to eq(%w[c-alpha#turn-0 c-alpha#turn-1])
    expect(logger).to have_received(:warn).with("json message skipped", hash_including(reason: "text_empty"))
  end

  it "logs text_missing for a message with a null text" do
    units_for([convo("c-alpha", msg("one"), { "text" => nil })])

    expect(logger).to have_received(:warn).with("json message skipped", hash_including(reason: "text_missing", record_index: 0))
  end

  it "skips a record of the wrong shape and keeps the rest of the file" do
    units = units_for([{ "name" => "no uuid" }, convo("c-beta", msg("after"))])

    expect(units.map(&:section_id)).to eq(["c-beta#turn-0"])
    expect(logger).to have_received(:warn).with("json record skipped", hash_including(reason: "no_document_key", record_index: 0))
  end

  it "logs one no_known_shape warning when the array has records and no document record" do
    expect(units_for([{ "name" => "a" }, { "name" => "b" }])).to eq([])
    expect(logger).to have_received(:warn).once.with("json array holds no document records", hash_including(reason: "no_known_shape"))
  end

  it "yields nothing and logs nothing for an empty array" do
    expect(units_for("[]")).to eq([])
    expect(logger).not_to have_received(:warn)
  end

  it "skips a repeated uuid, keeps the first, and lists it as skipped" do
    source = described_class.new(file_ref(write("c.json", [convo("c-alpha", msg("one")), convo("c-alpha", msg("two"))])), logger:)
    units = source.each_unit.to_a

    expect(units.map(&:text)).to eq(["one"])
    expect(source.skipped).to eq([{ record_index: 1, reason: "duplicate_document_key" }])
    expect(logger).to have_received(:warn).with("json record skipped", hash_including(reason: "duplicate_document_key", document_key: "c-alpha"))
  end

  it "skips a uuid containing # and logs it sanitized" do
    source = described_class.new(file_ref(write("c.json", [convo("c-alpha#turn-9", msg("one")), convo("c-beta", msg("after"))])), logger:)
    units = source.each_unit.to_a

    expect(units.map(&:document_key)).to eq(["c-beta"])
    expect(source.skipped).to eq([{ record_index: 0, reason: "invalid_document_key" }])
    expect(logger).to have_received(:warn).with("json record skipped", hash_including(document_key: "c-alpha#turn-9"))
  end

  it "keeps a message of 5 MiB whole" do
    big = "x" * 5_242_880
    units = units_for([convo("c-alpha", msg(big), msg("after"))])

    expect(units.map { |unit| unit.text.bytesize }).to eq([5_242_880, 5])
  end

  it "raises a Failure naming the file and byte offset for a truncated file" do
    path = write("t.json", %([{"uuid": "c-alpha", "chat_messages": []}, {"uuid": "c-beta", "chat_m))

    expect { described_class.new(file_ref(path), logger:).each_unit.to_a }
      .to raise_error(SFL::Core::Loaders::Error, /t\.json: truncated at byte #{File.size(path)}/)
  end

  it "keeps a conversation uuid from the file in document_keys before a failure" do
    path = write("t.json", %([{"uuid": "c-alpha", "chat_messages": [{"text": "a"}]}, {"uuid": "c-beta", "chat_m))
    source = described_class.new(file_ref(path), logger:)

    expect { source.each_unit.to_a }.to raise_error(SFL::Core::Loaders::Error)
    expect(source.document_keys).to eq(["c-alpha"])
  end

  it "sanitizes the file name in an error message" do
    path = File.join(dir, "bad\nname.json")
    File.write(path, "[")

    expect { described_class.new(file_ref(path), logger:).each_unit.to_a }
      .to raise_error(SFL::Core::Loaders::Error, /bad name\.json: truncated/)
  end
end
