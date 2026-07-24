# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::CitationGroundingChecker do
  subject(:checker) { described_class.new }

  let(:clause) do
    build_annotated_clause(
      id: "c1", document_id: "doc-1",
      text: "The system processes structured linguistic annotations."
    )
  end

  describe "#check" do
    it "marks a sentence grounded when its citation resolves and shares 2+ content words with the clause" do
      text = "The system processes structured data efficiently [c1]."

      result = checker.check(text, [clause])

      expect(result[:grounded]).to eq([{ sentence: text, citations: ["c1"] }])
      expect(result[:ungrounded]).to eq([])
    end

    it "marks a sentence ungrounded when it carries no citation marker at all" do
      text = "The system processes structured data efficiently."

      result = checker.check(text, [clause])

      expect(result[:ungrounded]).to eq([{ sentence: text, citations: [], reason: "no citation marker" }])
      expect(result[:grounded]).to eq([])
    end

    it "marks a sentence ungrounded when its citation resolves to no known clause" do
      text = "Something happened here [zzz]."

      result = checker.check(text, [clause])

      expect(result[:ungrounded]).to contain_exactly(
        a_hash_including(sentence: text, citations: ["zzz"], reason: "clause not found: zzz")
      )
    end

    it "marks a sentence ungrounded when it shares fewer than 2 content words with the cited clause" do
      text = "Weather is nice today [c1]."

      result = checker.check(text, [clause])

      expect(result[:ungrounded]).to eq(
        [{ sentence: text, citations: ["c1"], reason: "no keyword overlap with cited clause(s)" }]
      )
    end

    it "resolves a compound doc-id:clause-id citation by its clause-id suffix" do
      text = "The system processes structured data efficiently [doc-1:c1]."

      result = checker.check(text, [clause])

      expect(result[:grounded]).to eq([{ sentence: text, citations: ["doc-1:c1"] }])
    end

    it "computes coverage as grounded sentence count over total sentence count" do
      text = "The system processes structured data efficiently [c1]. Weather is nice today [c1]. " \
        "No marker here at all."

      result = checker.check(text, [clause])

      expect(result[:grounded].size).to eq(1)
      expect(result[:ungrounded].size).to eq(2)
      expect(result[:coverage]).to be_within(1e-9).of(1.0 / 3)
    end

    it "returns coverage 0.0 for empty narrative text (no sentences at all)" do
      result = checker.check("", [clause])

      expect(result).to eq(grounded: [], ungrounded: [], coverage: 0.0)
    end
  end
end
