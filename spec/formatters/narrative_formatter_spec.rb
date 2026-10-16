# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Formatters::NarrativeFormatter do
  let(:report) { build_narrative_report(source: "conv-1", generated_at: Time.new(2024, 1, 1, 0, 0, 0)) }
  let(:grounding_finding) do
    SFL::Analysis::DigestGroundingChecker::Finding.new(
      check: :number, section: :overview, sentence: "The tenor is 0.91.",
      detail: "0.91 has no digest value", band: :median, weight: 0.6
    )
  end
  let(:grounding) do
    SFL::Analysis::DigestGroundingChecker::Result.new(
      findings: [grounding_finding], claim_count: 4, weighted_total: 3.0, weighted_failed: 0.6
    )
  end

  describe "without grounding" do
    subject(:markdown) { described_class.new(report).render }

    it "renders the title, generation timestamp, and every fixed section" do
      expect(markdown).to include("# Narrative Report: conv-1")
      expect(markdown).to include("*Generated 2024-01-01T00:00:00")
      expect(markdown).to include("## Overview\n\nAn overview.")
      expect(markdown).to include("## Cast & Roles\n\nCast notes.")
      expect(markdown).to include("## Takeaways\n\nTakeaway notes.")
    end

    it "omits the Grounding Check section and the precision footer" do
      expect(markdown).not_to include("## Grounding Check")
      expect(markdown).not_to include("Weighted grounding precision")
    end

    it "no longer renders the citation-based Hallucination Report" do
      expect(markdown).not_to include("Hallucination Report")
      expect(markdown).not_to include("Citation coverage")
    end
  end

  describe "with grounding" do
    subject(:markdown) { described_class.new(report, grounding:).render }

    it "lists each flagged claim with its check, certainty band and weight" do
      expect(markdown).to include("## Grounding Check")
      expect(markdown).to include(
        '1. **number** (median, weight 0.6): "The tenor is 0.91." — 0.91 has no digest value'
      )
    end

    it "footers the weighted precision with the claim and flag counts" do
      expect(markdown).to include("*Weighted grounding precision: 80.0% (4 claims checked, 1 flagged)*")
    end

    it "states that nothing failed when there are no findings" do
      clean = SFL::Analysis::DigestGroundingChecker::Result.new(
        findings: [], claim_count: 2, weighted_total: 2.0, weighted_failed: 0.0
      )

      markdown = described_class.new(report, grounding: clean).render

      expect(markdown).to include("No checkable claim failed against the digest.")
      expect(markdown).to include("*Weighted grounding precision: 100.0% (2 claims checked, 0 flagged)*")
    end
  end
end
