# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::QualityScorer do
  subject(:scorer) { described_class.new }

  describe "#score" do
    it "returns 0.0 for an empty clause set, regardless of last_updated" do
      expect(scorer.score(clauses: [], last_updated: Time.now)).to eq(0.0)
    end

    it "uses a neutral 0.5 freshness signal when last_updated is unknown (nil)" do
      # source=1.0 (llm), modality=1.0, substance=1/20=0.05, freshness=0.5 (unknown)
      clauses = [build_annotated_clause(annotation_source: "llm", modality: 1.0)]

      score = scorer.score(clauses:, last_updated: nil)

      expected = ((1.0 * 0.40) + (1.0 * 0.30) + (0.05 * 0.20) + (0.5 * 0.10)).round(3)
      expect(score).to eq(expected)
    end

    it "weights annotation_source at 0.40, modality at 0.30, substance at 0.20, freshness at 0.10" do
      clauses = Array.new(20) { |i| build_annotated_clause(id: "c#{i}", annotation_source: "llm", modality: 1.0) }

      score = scorer.score(clauses:, last_updated: Time.now)

      # source=1.0, modality=1.0, substance=20/20=1.0 (capped), freshness=~1.0 (just updated)
      expect(score).to be_within(0.01).of(1.0)
    end

    it "scores fallback-sourced clauses lower than llm/human via SOURCE_WEIGHTS" do
      fallback = scorer.score(clauses: [build_annotated_clause(annotation_source: "fallback")], last_updated: Time.now)
      trusted = scorer.score(clauses: [build_annotated_clause(annotation_source: "llm")], last_updated: Time.now)

      expect(fallback).to be < trusted
    end

    it "scores stub-sourced clauses lower than fallback-sourced clauses via SOURCE_WEIGHTS (0.1 vs 0.4)" do
      stub = scorer.score(clauses: [build_annotated_clause(annotation_source: "stub")], last_updated: nil)
      fallback = scorer.score(clauses: [build_annotated_clause(annotation_source: "fallback")], last_updated: nil)

      expect(stub).to be < fallback
    end

    it "caps substance_score at 1.0 once clause count reaches SUBSTANCE_CEILING (20)" do
      at_ceiling = Array.new(20) { |i| build_annotated_clause(id: "c#{i}") }
      above_ceiling = Array.new(40) { |i| build_annotated_clause(id: "c#{i}") }

      expect(scorer.score(clauses: at_ceiling, last_updated: Time.now))
        .to eq(scorer.score(clauses: above_ceiling, last_updated: Time.now))
    end

    it "scores content just past the staleness cutoff at or near 0 freshness" do
      stale = Time.now - (19 * 30 * 24 * 60 * 60)
      fresh = Time.now

      stale_score = scorer.score(clauses: [build_annotated_clause], last_updated: stale)
      fresh_score = scorer.score(clauses: [build_annotated_clause], last_updated: fresh)

      expect(stale_score).to be < fresh_score
    end

    it "clamps the final score into 0.0..1.0" do
      score = scorer.score(clauses: [build_annotated_clause(annotation_source: "llm", modality: 1.0)],
        last_updated: Time.now)

      expect(score).to be_between(0.0, 1.0)
    end
  end
end
