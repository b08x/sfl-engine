# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::ProcessMixAnalyzer do
  def clause(speaker, process_type, source: "llm")
    { speaker:, process_type:, source: }
  end

  describe "#call" do
    # Trusted clauses: 8 in total.
    #   alice: material, material, material, mental          (4)
    #   bob:   material, relational, relational, relational   (4)
    # Baseline over all 8: material 4/8 = 0.5, mental 1/8 = 0.125, relational 3/8 = 0.375.
    # alice: material 0.75, mental 0.25, relational 0.0.
    #   deviation: +0.25, +0.125, -0.375. total_deviation = (0.25 + 0.125 + 0.375) / 2 = 0.375.
    # bob: material 0.25, mental 0.0, relational 0.75.
    #   deviation: -0.25, -0.125, +0.375. total_deviation = 0.375.
    # Two untrusted clauses (fallback, stub) are excluded from every count.
    let(:fixture) do
      [
        clause("alice", "material"),
        clause("alice", "material"),
        clause("alice", "material"),
        clause("alice", "mental"),
        clause("bob", "material"),
        clause("bob", "relational"),
        clause("bob", "relational"),
        clause("bob", "relational"),
        clause("alice", "verbal", source: "fallback"),
        clause("bob", "behavioral", source: "stub"),
      ]
    end

    it "computes the exact baseline and per-speaker shares and deviations" do
      result = described_class.new(fixture).call

      expect(result[:baseline]).to eq("material" => 0.5, "relational" => 0.375, "mental" => 0.125)

      alice = result[:per_speaker]["alice"]
      expect(alice[:distribution]).to eq("material" => 0.75, "relational" => 0.0, "mental" => 0.25)
      expect(alice[:deviation]["material"]).to be_within(1e-12).of(0.25)
      expect(alice[:deviation]["relational"]).to be_within(1e-12).of(-0.375)
      expect(alice[:deviation]["mental"]).to be_within(1e-12).of(0.125)
      expect(alice[:total_deviation]).to be_within(1e-12).of(0.375)

      bob = result[:per_speaker]["bob"]
      expect(bob[:distribution]["relational"]).to be_within(1e-12).of(0.75)
      expect(bob[:deviation]["relational"]).to be_within(1e-12).of(0.375)
      expect(bob[:total_deviation]).to be_within(1e-12).of(0.375)
    end

    it "excludes clauses whose source is not llm or human" do
      result = described_class.new(fixture).call

      expect(result[:baseline].keys).not_to include("verbal", "behavioral")
      expect(result[:per_speaker]["alice"][:distribution].keys).not_to include("verbal")
    end

    it "counts human-sourced clauses as trusted" do
      clauses = [clause("alice", "mental", source: "human"), clause("alice", "verbal", source: "chunk_artifact")]

      result = described_class.new(clauses).call

      expect(result[:baseline]).to eq("mental" => 1.0)
    end

    it "gives total_deviation 0.0 for a speaker identical to the baseline" do
      clauses = [
        clause("x", "material"),
        clause("x", "relational"),
        clause("y", "material"),
        clause("y", "relational"),
      ]

      result = described_class.new(clauses).call

      expect(result[:per_speaker]["x"][:total_deviation]).to eq(0.0)
      expect(result[:per_speaker]["y"][:total_deviation]).to eq(0.0)
    end

    it "returns an empty baseline and per_speaker for empty input" do
      expect(described_class.new([]).call).to eq(baseline: {}, per_speaker: {})
    end

    it "returns an empty baseline and per_speaker when no clause is trusted" do
      clauses = [clause("alice", "material", source: "fallback")]

      expect(described_class.new(clauses).call).to eq(baseline: {}, per_speaker: {})
    end
  end
end
