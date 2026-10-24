# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::SillyTavernSource::MesText do
  describe ".extract" do
    it "returns a String unchanged apart from surrounding whitespace" do
      expect(described_class.extract("  hi there ")).to eq("hi there")
    end

    it "joins the String elements of an array with a newline" do
      expect(described_class.extract(%w[one two])).to eq("one\ntwo")
    end

    it "collects String leaves depth-first in document order" do
      mes = [{ "a" => "first", "b" => ["second", { "c" => "third" }] }, "fourth"]

      expect(described_class.extract(mes)).to eq("first\nsecond\nthird\nfourth")
    end

    it "does not treat hash keys as text" do
      expect(described_class.extract({ "key" => { "other" => "value" } })).to eq("value")
    end

    it "contributes nothing for numbers, booleans and nil elements" do
      expect(described_class.extract([1, true, false, nil, 2.5, "text"])).to eq("text")
    end

    it "returns an empty string when there is no String leaf" do
      expect(described_class.extract([])).to eq("")
      expect(described_class.extract(42)).to eq("")
      expect(described_class.extract(false)).to eq("")
      expect(described_class.extract({ "n" => 1 })).to eq("")
    end

    it "strips whitespace from the joined text, including a leading empty leaf" do
      expect(described_class.extract(["", "  body  "])).to eq("body")
    end
  end
end
