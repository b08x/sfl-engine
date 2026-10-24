# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::SillyTavernSource::SingleLine do
  it "replaces a newline with a single space" do
    expect(described_class.call("bad\nname.jsonl")).to eq("bad name.jsonl")
  end

  it "replaces a carriage return and a tab with spaces and collapses the run" do
    expect(described_class.call("a\r\n\tb")).to eq("a b")
  end

  it "replaces an ANSI escape introducer with a space" do
    expect(described_class.call("\e[31mx")).to eq("[31mx")
  end

  it "strips the ends after sanitizing" do
    expect(described_class.call(" \n name \t ")).to eq("name")
  end

  it "keeps a long value whole, with no length cap" do
    expect(described_class.call("a" * 200)).to eq("a" * 200)
  end

  it "gives an empty String for a value that is only whitespace and control characters" do
    expect(described_class.call(" \n\t\e ")).to eq("")
  end

  it "replaces invalid UTF-8 bytes instead of raising" do
    expect(described_class.call("ok\xFFname".b.force_encoding("UTF-8"))).to eq("ok�name")
  end
end
