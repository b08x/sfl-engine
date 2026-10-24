# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe SFL::Core::Loaders::JsonRecordsSource::ArraySplitter::TokenReader do
  def reader(text, file: "f.json")
    described_class.new(StringIO.new(text.b), file:)
  end

  def tokens(reader)
    [].tap do |out|
      while (token = reader.next_token)
        out << token
      end
    end
  end

  it "returns kind, start and length for each token" do
    text = %([ "a", 12 ])
    kinds = tokens(reader(text)).map(&:first)

    expect(kinds).to eq(%i[punct space string punct space literal space punct])
  end

  it "reads the text of a token by start and length" do
    rd = reader(%(["ab"]))
    _, start, length = rd.next_token

    expect(start).to eq(0)
    expect(rd.text(start, length)).to eq("[")
  end

  it "returns absolute offsets across compaction" do
    stub_const("#{described_class}::CHUNK", 4)
    rd = reader(%([1,2,3,4,5,6,7,8,9]))
    last = tokens(rd).last

    expect(rd.absolute(last[1])).to eq(18)
  end

  it "raises truncated at the end of the input for a token that never closes" do
    rd = reader(%(["abc))

    expect { tokens(rd) }.to raise_error(SFL::Core::Loaders::JsonRecordsSource::Failure) { |error|
      expect(error).to have_attributes(reason: "truncated", byte_offset: 5)
    }
  end
end
