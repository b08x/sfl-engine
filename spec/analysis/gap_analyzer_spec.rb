# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::GapAnalyzer do
  # Builds one conversation from gaps (seconds between consecutive turns) and
  # spike flags (one per turn, so spikes.size == gaps.size + 1).
  def conversation_from(gaps, spikes)
    time = Time.at(0)
    timestamps = [time] + gaps.map { |gap| time += gap }
    { turns: timestamps.zip(spikes).map { |ts, spike| { timestamp: ts, spike: } } }
  end

  describe ".percentile" do
    it "interpolates linearly between order statistics" do
      expect(described_class.percentile([1, 2, 3, 4], 75)).to be_within(1e-12).of(3.25)
    end

    it "returns the single value for a one-element collection" do
      expect(described_class.percentile([42], 75)).to eq(42)
    end
  end

  describe ".fisher_exact" do
    # Hand computation for [[8, 2], [2, 8]]: N = 20, row totals 10 and 10, column totals 10 and 10.
    # P(k) = C(10, k)^2 / C(20, 10), with C(20, 10) = 184756.
    # Observed k = 8 has C(10, 8)^2 = 2025. Outcomes with P <= 2025 are k = 0, 1, 2, 8, 9, 10,
    # with weights 1 + 100 + 2025 + 2025 + 100 + 1 = 4252.
    # p = 4252 / 184756 = 1063 / 46189 = 0.02301414...
    it "matches the hand-computed two-sided p-value for [[8, 2], [2, 8]]" do
      expect(described_class.fisher_exact([[8, 2], [2, 8]])).to be_within(1e-6).of(1063.0 / 46_189.0)
    end

    # Hand computation for [[3, 1], [1, 3]]: N = 8, all margins 4, P(k) = C(4, k)^2 / 70.
    # Weights for k = 0..4 are 1, 16, 36, 16, 1. Observed k = 3 has weight 16.
    # Outcomes with weight <= 16 are k = 0, 1, 3, 4, total 34 / 70 = 0.4857142857.
    it "matches the hand-computed value for [[3, 1], [1, 3]]" do
      expect(described_class.fisher_exact([[3, 1], [1, 3]])).to be_within(1e-6).of(34.0 / 70.0)
    end
  end

  describe "#call" do
    it "flags no long pause when every gap is below the floor" do
      # Gaps 60, 60, 880, 60, 60 have a 75th percentile of 60. The 880 gap is above it,
      # but a floor of 1000 excludes it.
      conversation = conversation_from([60, 60, 880, 60, 60], [true, false, false, true, false, false])

      result = described_class.new([conversation], floor_seconds: 1000).call

      expect(result[:long_pause_threshold_seconds]).to eq(1000)
      expect(result[:after_long_pause]).to eq(turns: 0, spikes: 0, rate: nil)
      expect(result[:other]).to eq(turns: 6, spikes: 2, rate: 2.0 / 6.0)
      expect(result[:p_value]).to be_nil
      expect(result[:method]).to be_nil
      expect(result[:reason]).to eq("no long pause in any conversation")
    end

    # Gaps 60, 60, 880, 60, 60 (floor 600). Only the 880 gap is a long pause, so turn 3 is after one.
    # Table: after = [spike 1, nonspike 0], other = [spike 1, nonspike 4].
    # Expected cell for row 1 and column 1 is 1 * 2 / 6 = 0.33, below 5, so the permutation test runs.
    # The table has 2 spikes over 6 turns. The observed gap is |1 - 1/5| = 0.8. A permutation
    # reaches a gap of at least 0.8 only when the single after slot receives a spike, which
    # has probability 2 / 6 = 1 / 3. So p is about 1 / 3, estimated as (hits + 1) / 10001.
    it "uses the permutation test when an expected cell is below 5, reproducibly for a fixed seed" do
      conversation = conversation_from([60, 60, 880, 60, 60], [true, false, false, true, false, false])

      first = described_class.new([conversation], seed: 42).call
      second = described_class.new([conversation], seed: 42).call

      expect(first[:method]).to eq("permutation")
      expect(first[:after_long_pause]).to eq(turns: 1, spikes: 1, rate: 1.0)
      expect(first[:other]).to eq(turns: 5, spikes: 1, rate: 0.2)
      expect(first[:p_value]).to be_within(0.01).of(1.0 / 3.0)
      expect(first[:p_value]).to eq(second[:p_value])
    end

    # Each turn gap is compared with the conversation's own percentile. 39 gaps: 29 at 60 s and
    # 10 at 900 s. The 75th percentile is 60 + 0.5 * (900 - 60) = 480 s (rank 28.5), so the 10
    # gaps of 900 s are long pauses. Turns 30..39 are after one. The table is
    # [[8, 2], [12, 18]]. Expected cells are 5, 5, 15, 15, so the exact test runs.
    it "uses the exact Fisher test when every expected cell is at least 5" do
      gaps = Array.new(29, 60) + Array.new(10, 900)
      spikes = Array.new(30) { |i| i < 12 } + Array.new(10) { |i| i < 8 }
      conversation = conversation_from(gaps, spikes)

      result = described_class.new([conversation]).call

      expect(result[:method]).to eq("exact")
      expect(result[:after_long_pause]).to eq(turns: 10, spikes: 8, rate: 0.8)
      expect(result[:other]).to eq(turns: 30, spikes: 12, rate: 0.4)
      expect(result[:p_value]).to be_within(1e-12).of(described_class.fisher_exact([[8, 2], [12, 18]]))
      expect(result[:reason]).to be_nil
    end

    it "returns no pauses and a nil p-value with a stated reason for an empty conversation" do
      result = described_class.new([{ turns: [] }]).call

      expect(result[:after_long_pause]).to eq(turns: 0, spikes: 0, rate: nil)
      expect(result[:other]).to eq(turns: 0, spikes: 0, rate: nil)
      expect(result[:p_value]).to be_nil
      expect(result[:method]).to be_nil
      expect(result[:reason]).to eq("no long pause in any conversation")
    end

    it "returns no pauses and a nil p-value with a stated reason for a single-turn conversation" do
      conversation = conversation_from([], [true])

      result = described_class.new([conversation]).call

      expect(result[:after_long_pause][:turns]).to eq(0)
      expect(result[:other]).to eq(turns: 1, spikes: 1, rate: 1.0)
      expect(result[:p_value]).to be_nil
      expect(result[:reason]).to eq("no long pause in any conversation")
    end

    it "returns the empty result for no conversations" do
      result = described_class.new([]).call

      expect(result[:p_value]).to be_nil
      expect(result[:other][:turns]).to eq(0)
    end
  end
end
