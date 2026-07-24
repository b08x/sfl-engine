# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Formatters::NarrativeFormatter do
  let(:report) { build_narrative_report(source: "conv-1", generated_at: Time.new(2024, 1, 1, 0, 0, 0)) }

  describe "without citation_check" do
    subject(:markdown) { described_class.new(report).render }

    it "renders the title, generation timestamp, and every fixed section" do
      expect(markdown).to include("# Narrative Report: conv-1")
      expect(markdown).to include("*Generated 2024-01-01T00:00:00")
      expect(markdown).to include("## Overview\n\nAn overview.")
      expect(markdown).to include("## Cast & Roles\n\nCast notes.")
      expect(markdown).to include("## Takeaways\n\nTakeaway notes.")
    end

    it "omits the Hallucination Report and coverage footer" do
      expect(markdown).not_to include("Hallucination Report")
      expect(markdown).not_to include("Citation coverage")
    end
  end

  describe "with citation_check" do
    subject(:markdown) { described_class.new(report, citation_check:).render }

    let(:citation_check) do
      {
        grounded: [{ sentence: "A grounded claim.", citations: ["c1"] }],
        ungrounded: [{ sentence: "An ungrounded claim.", citations: [], reason: "no citation marker" }],
      }
    end

    it "appends a Hallucination Report listing each ungrounded claim" do
      expect(markdown).to include("## Hallucination Report")
      expect(markdown).to include('1. **UNGROUNDED**: "An ungrounded claim." — no citation marker')
    end

    it "appends a citation coverage footer" do
      expect(markdown).to include("*Citation coverage: 1/2 claims grounded (50.0%)*")
    end

    it "omits the Hallucination Report section when nothing is ungrounded" do
      fully_grounded = { grounded: citation_check[:grounded], ungrounded: [] }

      expect(described_class.new(report, citation_check: fully_grounded).render).not_to include("Hallucination Report")
    end
  end
end
