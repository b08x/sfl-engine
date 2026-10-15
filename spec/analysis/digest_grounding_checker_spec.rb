# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::DigestGroundingChecker do
  subject(:checker) { described_class.new }

  # Six turns, two speakers. Turn 2 carries a KEY MOMENT and a tenor_shift, and
  # no other turn has either. Turn 1 has no shift; turn 2 has one.
  let(:turns) do
    [
      {
        "turn_id" => 1,
        "speaker" => "Alice",
        "preview" => "I think the deadline is Friday, and we should keep it.",
        "avg_tenor" => 0.62,
        "avg_modality" => 0.8,
        "dominant_mood" => "declarative",
        "tenor_shift" => nil,
        "clause_count" => 2,
        "defaulted_count" => 0,
      },
      {
        "turn_id" => 2,
        "speaker" => "Bob",
        "preview" => "Why would we move it to Monday? That makes no sense.",
        "avg_tenor" => 0.31,
        "avg_modality" => 0.4,
        "dominant_mood" => "interrogative",
        "tenor_shift" => 0.4,
        "clause_count" => 2,
        "defaulted_count" => 0,
      },
      {
        "turn_id" => 3,
        "speaker" => "Alice",
        "preview" => "Please send the revised plan to the team today.",
        "avg_tenor" => 0.7,
        "avg_modality" => 0.5,
        "dominant_mood" => "imperative",
        "tenor_shift" => nil,
        "clause_count" => 1,
        "defaulted_count" => 0,
      },
      {
        "turn_id" => 4,
        "speaker" => "Bob",
        "preview" => "Fine, I will check the numbers again.",
        "avg_tenor" => 0.5,
        "avg_modality" => 0.5,
        "dominant_mood" => "declarative",
        "tenor_shift" => nil,
        "clause_count" => 1,
        "defaulted_count" => 0,
      },
      {
        "turn_id" => 5,
        "speaker" => "Alice",
        "preview" => "Thanks, all done here for now.",
        "avg_tenor" => 0.6,
        "avg_modality" => 0.5,
        "dominant_mood" => "declarative",
        "tenor_shift" => nil,
        "clause_count" => 1,
        "defaulted_count" => 0,
      },
      {
        "turn_id" => 6,
        "speaker" => "Bob",
        "preview" => "Agreed, closing the thread.",
        "avg_tenor" => 0.5,
        "avg_modality" => 0.5,
        "dominant_mood" => "declarative",
        "tenor_shift" => nil,
        "clause_count" => 1,
        "defaulted_count" => 0,
      },
    ]
  end

  let(:digest) do
    SFL::Analysis::NarrativeGenerator::Digest.new(
      metadata: { "conversation_id" => "fixture", "clause_count" => 8 },
      speaker_profiles: {},
      correlations: {},
      insights: [],
      turns:,
      key_moments: [{ "type" => "pivot", "turn_id" => 2, "magnitude" => 0.4, "description" => "reversal" }]
    )
  end

  def check_text(text)
    checker.check({ overview: text }, digest)
  end

  def failed_checks(text)
    check_text(text).findings.map(&:check)
  end

  describe "numbers" do
    it "passes a decimal that matches a digest value within 0.005" do
      expect(failed_checks("The average tenor is 0.62.")).to be_empty
    end

    it "flags a decimal with no digest value" do
      expect(failed_checks("The average tenor is 0.91.")).to include(:number)
    end

    it "passes a percentage that matches a 0–1 digest value within 0.5 points" do
      expect(failed_checks("The shift is 40%.")).to be_empty
    end

    it "flags a percentage with no digest value" do
      expect(failed_checks("The shift reached 75%.")).to include(:number)
    end

    it "flags an integer that no digest value matches exactly" do
      expect(failed_checks("There are 99 clauses.")).to include(:number)
    end

    it "ignores numbers inside a quoted message" do
      expect(failed_checks("Bob writes \"I have 99 reasons\" in turn 2.")).not_to include(:number)
    end
  end

  describe "turn references" do
    it "passes a reference to an existing turn" do
      expect(failed_checks("Turn 2 asks a question.")).to be_empty
    end

    it "flags a turn that does not exist" do
      expect(failed_checks("Turn 9 closes the thread.")).to include(:turn_reference)
    end

    it "flags a speaker that contradicts the turn row" do
      expect(failed_checks("Bob says in turn 1 that the deadline holds.")).to include(:turn_attribute)
    end

    it "passes a speaker that matches the turn row" do
      expect(failed_checks("Alice says in turn 1 that the deadline holds.")).to be_empty
    end

    it "flags a mood that contradicts the turn row" do
      expect(failed_checks("Turn 3 is interrogative.")).to include(:turn_attribute)
    end

    it "flags a tenor shift claimed for a turn that has none" do
      expect(failed_checks("Turn 1 shows a tenor shift.")).to include(:turn_attribute)
    end

    it "passes a tenor shift claimed for a turn that has one" do
      expect(failed_checks("Turn 2 shows a tenor shift.")).not_to include(:turn_attribute)
    end
  end

  describe "quotes" do
    it "passes a quote of four or more words found in a turn preview" do
      expect(failed_checks("Alice writes \"the deadline is Friday, and we should keep it\" in turn 1.")).to be_empty
    end

    it "flags a quote of four or more words found in no preview" do
      expect(failed_checks("Alice writes \"we should move the launch to Tuesday\" early on.")).to include(:quote)
    end

    it "does not check quotes shorter than four words" do
      expect(failed_checks("Alice calls it \"the deadline\".")).not_to include(:quote)
    end

    it "accepts a near-match above the Jaro-Winkler threshold" do
      expect(failed_checks("Alice writes \"the deadline is Fridays and we should keep it\".")).not_to include(:quote)
    end
  end

  describe "causal connectives" do
    it "passes a causal claim on a turn with a KEY MOMENT" do
      expect(failed_checks("Turn 2 reverses the plan because it is a pivot.")).not_to include(:causal_connective)
    end

    it "flags a causal claim with no KEY MOMENT or shift nearby, as fabricated causation" do
      result = check_text("Turn 5 is a reply because Alice was annoyed.")

      expect(result.findings.map(&:check)).to include(:causal_connective)
      expect(result.fabricated_causation).to eq(1)
    end

    it "treats a KEY MOMENT on an adjacent turn as support" do
      expect(failed_checks("Turn 3 is brief because Bob had objected.")).not_to include(:causal_connective)
    end
  end

  describe "temporal connectives" do
    it "passes turns cited in turn order" do
      expect(failed_checks("First, turn 1 sets the deadline, then turn 3 repeats it.")).not_to include(:temporal_connective)
    end

    it "flags turns cited against turn order" do
      expect(failed_checks("Then turn 3 answers, and after that turn 1 objects.")).to include(:temporal_connective)
    end
  end

  describe "certainty weighting" do
    it "weights an unmarked failure at 1.0" do
      finding = check_text("Turn 9 closes the thread.").findings.first

      expect(finding.weight).to eq(1.0)
      expect(finding.band).to be_nil
    end

    it "weights a hedged failure at 0.3, below an asserted one" do
      hedged = check_text("Turn 9 may close the thread.").findings.first
      asserted = check_text("Turn 9 must close the thread.").findings.first

      expect(hedged.weight).to eq(0.3)
      expect(asserted.weight).to eq(1.0)
    end

    it "computes weighted precision from failed and total claim weight" do
      result = check_text("Turn 9 may close the thread. The average tenor is 0.62.")

      expect(result.weighted_failed).to be_within(1e-9).of(0.3)
      expect(result.weighted_precision).to be_within(1e-9).of(1.0 - (0.3 / result.weighted_total))
    end

    it "reports precision 1.0 for a narrative with no checkable claims" do
      expect(check_text("The conversation was short.").weighted_precision).to eq(1.0)
    end
  end
end
