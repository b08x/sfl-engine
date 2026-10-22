# frozen_string_literal: true

require "spec_helper"

# Facts 9 and 10: default collection name and the trim/case/empty rules.
RSpec.describe SFL::Core::CollectionName do
  describe ".normalize" do
    it "trims surrounding whitespace and keeps case" do
      expect(described_class.normalize("  Field Notes \n")).to eq("Field Notes")
    end

    it "rejects an empty or blank name" do
      expect { described_class.normalize("   ") }.to raise_error(described_class::Error, /must not be empty/)
      expect { described_class.normalize(nil) }.to raise_error(described_class::Error)
    end
  end

  describe ".default_for" do
    it "is the basename of the input directory" do
      expect(described_class.default_for("/data/papers/")).to eq("papers")
      expect(described_class.default_for("./inbox")).to eq("inbox")
    end
  end
end
