# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe SFL::Core::Loaders::JsonRecordsSource::ArraySplitter do
  def split(text, chunk: nil)
    io = StringIO.new(text.b)
    splitter = described_class.new(io, file: "f.json")
    stub_const("#{described_class}::TokenReader::CHUNK", chunk) if chunk
    splitter.each_element.to_a
  end

  def fault_for(text, **)
    split(text, **)
    raise "expected a Failure"
  rescue SFL::Core::Loaders::JsonRecordsSource::Failure => e
    e
  end

  it "yields each element's raw text, byte offset and index" do
    elements = split(%([{"a": 1}, "two", 3, [4, 5]]))

    expect(elements.map(&:first)).to eq(['{"a": 1}', '"two"', "3", "[4, 5]"])
    expect(elements.map(&:last)).to eq([0, 1, 2, 3])
    expect(elements[0][1]).to eq(1)
  end

  it "yields nothing for an empty array" do
    expect(split("[ ]")).to eq([])
  end

  it "keeps a string containing brackets and an escaped quote inside one element" do
    elements = split(%(["a ] } \\" [ ", 1]))

    expect(elements.first.first).to eq(%("a ] } \\" [ "))
  end

  it "reads across chunk boundaries without splitting a token" do
    text = %([{"uuid": "c-alpha", "chat_messages": [{"text": "hello world"}]}, 42])

    expect(split(text, chunk: 3).map(&:first)).to eq(split(text).map(&:first))
  end

  it "rejects a top-level value that is not an array with byte_offset 0" do
    expect(fault_for(%({"a": 1}))).to have_attributes(reason: "not_an_array", byte_offset: 0, file: "f.json")
  end

  it "rejects a stray closing brace in place of a comma" do
    error = fault_for(%([{"a": 1}} , {"b": 2}]))

    expect(error).to have_attributes(reason: "parse_error", byte_offset: 9)
  end

  it "rejects a missing comma between elements" do
    expect(fault_for(%([{"a": 1} {"b": 2}])).reason).to eq("parse_error")
  end

  it "rejects a trailing comma" do
    expect(fault_for("[1,]").reason).to eq("parse_error")
  end

  it "rejects content after the closing bracket" do
    expect(fault_for("[1] x").reason).to eq("parse_error")
  end

  it "reports truncation at the file size, with the partial element when one is open" do
    text = %([{"uuid": "c-omega", "chat_messages": [{)
    error = fault_for(text)

    expect(error).to have_attributes(reason: "truncated", byte_offset: text.bytesize, partial: %({"uuid": "c-omega", "chat_messages": [{))
  end

  it "reports truncation with no partial element after a complete element and a comma" do
    error = fault_for(%([{"a": 1},))

    expect(error).to have_attributes(reason: "truncated", partial: nil)
  end

  it "reports truncation for an empty input" do
    expect(fault_for("").reason).to eq("truncated")
  end
end
