# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::JsonRecordsSource::MessageText do
  it "returns a String text as it is" do
    expect(described_class.extract({ "text" => "hello" })).to eq("hello")
  end

  it "returns nil when there is no text key or the text is null" do
    expect(described_class.extract({ "content" => "x" })).to be_nil
    expect(described_class.extract({ "text" => nil })).to be_nil
    expect(described_class.extract("a string")).to be_nil
  end

  it "returns an empty String for a non-String value with no String inside" do
    expect(described_class.extract({ "text" => 42 })).to eq("")
  end

  it "joins the non-blank Strings of an array with one line break" do
    expect(described_class.extract({ "text" => ["first", " ", "second"] })).to eq("first\nsecond")
  end

  it "takes Strings from nested hashes and arrays in order" do
    expect(described_class.extract({ "text" => { "count" => 2, "outer" => { "inner" => "nested" } } })).to eq("nested")
  end

  it "walks a deeply nested array without recursion" do
    deep = "deep"
    100_000.times { deep = [deep] }

    expect(described_class.extract({ "text" => deep })).to eq("deep")
  end
end
