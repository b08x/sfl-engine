# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::ClassificationRegistry do
  describe ".normalize" do
    it "returns the canonical value with :exact for an already-canonical value" do
      expect(described_class.normalize(:mood, "declarative")).to eq(["declarative", :exact])
    end

    it "resolves a known alias with :aliased" do
      expect(described_class.normalize(:mood, "question")).to eq(["interrogative", :aliased])
    end

    it "fuzzy-matches a near-miss with :fuzzy" do
      expect(described_class.normalize(:mood, "imperitive")).to eq(["imperative", :fuzzy])
    end

    it "falls through to the dimension default with :unknown for garbage input" do
      expect(described_class.normalize(:mood, "xyzzy_totally_unrelated")).to eq(["declarative", :unknown])
    end

    it "raises on an unknown dimension" do
      expect { described_class.normalize(:bogus, "x") }.to raise_error(ArgumentError)
    end
  end

  describe ".canonical_values" do
    it "returns the mood canonical set" do
      expect(described_class.canonical_values(:mood)).to include("declarative", "interrogative", "imperative")
    end
  end
end
