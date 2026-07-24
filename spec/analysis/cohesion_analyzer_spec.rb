# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::CohesionAnalyzer do
  subject(:analyzer) { described_class.new }

  describe "#analyze" do
    it "returns turns with default (all-zero) cohesion metrics when a turn has no clauses" do
      turn = build_turn(clauses: [])

      result = analyzer.analyze([turn])

      expect(result.first.cohesion.repetition_score).to eq(0.0)
      expect(result.first.cohesion.conjunction_density).to eq(0.0)
      expect(result.first.cohesion.pronoun_density).to eq(0.0)
    end

    it "returns default cohesion metrics when clauses exist but carry no tokens" do
      clause = build_annotated_clause(tokens: [])
      turn = build_turn(clauses: [clause])

      result = analyzer.analyze([turn])

      expect(result.first.cohesion.repetition_score).to eq(0.0)
    end

    it "does not mutate the original turns (returns new turn instances via #new)" do
      turn = build_turn(clauses: [])

      result = analyzer.analyze([turn])

      expect(turn.cohesion).to be_nil
      expect(result.first).not_to be(turn)
    end

    it "computes repetition_score as 1.0 minus the ratio of unique content lemmas to total content lemmas" do
      tokens = [
        build_token(text: "cat", lemma: "cat", pos: "NOUN"),
        build_token(text: "cat", lemma: "cat", pos: "NOUN"),
        build_token(text: "ran", lemma: "run", pos: "VERB"),
      ]
      clause = build_annotated_clause(tokens:)
      turn = build_turn(clauses: [clause])

      result = analyzer.analyze([turn])

      # content_lemmas = [cat, cat, run] -> unique 2 / total 3 -> 1 - 2/3 = 0.333...
      expect(result.first.cohesion.repetition_score).to be_within(0.001).of(0.333)
    end

    it "returns 0.0 repetition_score when there is 1 or fewer content lemmas" do
      tokens = [build_token(text: "cat", lemma: "cat", pos: "NOUN")]
      clause = build_annotated_clause(tokens:)
      turn = build_turn(clauses: [clause])

      result = analyzer.analyze([turn])

      expect(result.first.cohesion.repetition_score).to eq(0.0)
    end

    it "computes conjunction_density as the fraction of tokens tagged CCONJ or SCONJ" do
      tokens = [
        build_token(text: "and", pos: "CCONJ"),
        build_token(text: "because", pos: "SCONJ"),
        build_token(text: "cat", pos: "NOUN"),
        build_token(text: "ran", pos: "VERB"),
      ]
      clause = build_annotated_clause(tokens:)
      turn = build_turn(clauses: [clause])

      result = analyzer.analyze([turn])

      expect(result.first.cohesion.conjunction_density).to eq(0.5)
    end

    it "computes pronoun_density as the fraction of tokens tagged PRON" do
      tokens = [
        build_token(text: "it", pos: "PRON"),
        build_token(text: "cat", pos: "NOUN"),
        build_token(text: "ran", pos: "VERB"),
        build_token(text: "fast", pos: "ADV"),
      ]
      clause = build_annotated_clause(tokens:)
      turn = build_turn(clauses: [clause])

      result = analyzer.analyze([turn])

      expect(result.first.cohesion.pronoun_density).to eq(0.25)
    end

    it "pools tokens across every clause in the turn, not just the first" do
      c1 = build_annotated_clause(id: "c1", tokens: [build_token(text: "it", pos: "PRON")])
      c2 = build_annotated_clause(id: "c2", tokens: [build_token(text: "dog", pos: "NOUN")])
      turn = build_turn(clauses: [c1, c2])

      result = analyzer.analyze([turn])

      expect(result.first.cohesion.pronoun_density).to eq(0.5)
    end
  end
end
