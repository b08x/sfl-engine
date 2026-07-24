# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::LLM::ResponseSymbolizer do
  describe ".call" do
    it "symbolizes top-level and nested Hash keys" do
      result = described_class.call({ "a" => 1, "b" => { "c" => 2 } })

      expect(result).to eq({ a: 1, b: { c: 2 } })
    end

    it "symbolizes Hash keys inside Arrays" do
      result = described_class.call([{ "x" => 1 }, { "y" => 2 }])

      expect(result).to eq([{ x: 1 }, { y: 2 }])
    end

    it "leaves non-Hash, non-Array values untouched" do
      expect(described_class.call("plain string")).to eq("plain string")
      expect(described_class.call(42)).to eq(42)
      expect(described_class.call(nil)).to be_nil
    end
  end
end
