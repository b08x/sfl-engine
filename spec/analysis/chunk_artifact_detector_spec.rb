# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::ChunkArtifactDetector do
  # Plain #text duck — no verifiable class exists for "anything with #text",
  # matching this project's RSpec/VerifiedDoubles convention for ducks.
  def clause(text)
    double("clause", text:) # rubocop:disable RSpec/VerifiedDoubles -- plain #text duck, no verifiable class
  end

  describe ".detect" do
    it "flags both sides of a boundary when the prior clause lacks terminal punctuation and " \
      "the next clause starts lowercase" do
      clauses = [clause("Intro."), clause("The system was"), clause("designed for scale.")]

      expect(described_class.detect(clauses, [2])).to eq([1, 2])
    end

    it "flags both sides of a boundary when the next clause opens with a continuation word" do
      clauses = [clause("Intro."), clause("The team decided"), clause("because the deadline moved.")]

      expect(described_class.detect(clauses, [2])).to eq([1, 2])
    end

    it "does not flag a boundary when the prior clause ends with terminal punctuation" do
      clauses = [clause("Intro."), clause("The system works."), clause("Designed for scale.")]

      expect(described_class.detect(clauses, [2])).to eq([])
    end

    it "does not flag a boundary when the next clause starts capitalized and isn't a continuation word" do
      clauses = [clause("Intro."), clause("The system was"), clause("Scale matters too")]

      expect(described_class.detect(clauses, [2])).to eq([])
    end

    it "ignores a boundary at index 0 (no predecessor to check)" do
      clauses = [clause("Only one.")]

      expect(described_class.detect(clauses, [0])).to eq([])
    end

    it "ignores a boundary at or past clauses.size (no successor to check)" do
      clauses = [clause("First"), clause("Second.")]

      expect(described_class.detect(clauses, [2])).to eq([])
    end

    it "dedupes and sorts affected indices when multiple consecutive boundaries overlap" do
      clauses = [clause("A"), clause("the rest"), clause("continues"), clause("and more")]

      expect(described_class.detect(clauses, [1, 2, 3])).to eq([0, 1, 2, 3])
    end

    it "returns [] when given no boundaries" do
      clauses = [clause("Anything.")]

      expect(described_class.detect(clauses, [])).to eq([])
    end
  end
end
