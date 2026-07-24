# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::TenorTracker do
  describe "#calculate_shifts" do
    it "leaves the first turn's tenor_shift nil (no predecessor to diff against)" do
      turns = [build_turn(turn_id: 1, avg_tenor: 0.4), build_turn(turn_id: 2, avg_tenor: 0.6)]

      result = described_class.new(turns).calculate_shifts

      expect(result.first.tenor_shift).to be_nil
    end

    it "sets each subsequent turn's tenor_shift to the delta from the previous turn's avg_tenor" do
      turns = [
        build_turn(turn_id: 1, avg_tenor: 0.4),
        build_turn(turn_id: 2, avg_tenor: 0.6),
        build_turn(turn_id: 3, avg_tenor: 0.5),
]

      result = described_class.new(turns).calculate_shifts

      expect(result[1].tenor_shift).to be_within(1e-9).of(0.2)
      expect(result[2].tenor_shift).to be_within(1e-9).of(-0.1)
    end

    it "is a pure function: it does not mutate the array or structs passed in" do
      turns = [build_turn(turn_id: 1, avg_tenor: 0.4), build_turn(turn_id: 2, avg_tenor: 0.6)]
      original_second_turn = turns[1]
      tracker = described_class.new(turns)

      result = tracker.calculate_shifts

      expect(turns[1]).to equal(original_second_turn)
      expect(turns[1].tenor_shift).to be_nil
      expect(tracker.turns[1].tenor_shift).to be_nil
      expect(result[1].tenor_shift).to be_within(1e-9).of(0.2)
    end

    it "returns an empty array when given no turns" do
      expect(described_class.new([]).calculate_shifts).to eq([])
    end
  end

  describe "#detect_significant_shifts" do
    it "auto-runs calculate_shifts when shifts haven't been computed yet" do
      turns = [build_turn(turn_id: 1, avg_tenor: 0.1), build_turn(turn_id: 2, avg_tenor: 0.6)]

      shifts = described_class.new(turns, threshold: 0.15).detect_significant_shifts

      expect(shifts.size).to eq(1)
      expect(shifts.first[:turn_id]).to eq(2)
    end

    it "excludes shifts at or below the threshold" do
      turns = [build_turn(turn_id: 1, avg_tenor: 0.5), build_turn(turn_id: 2, avg_tenor: 0.6)]

      shifts = described_class.new(turns, threshold: 0.15).detect_significant_shifts

      expect(shifts).to be_empty
    end

    it "labels a positive shift 'more formal' and a negative shift 'less formal'" do
      turns = [
        build_turn(turn_id: 1, avg_tenor: 0.2),
        build_turn(turn_id: 2, avg_tenor: 0.8),
        build_turn(turn_id: 3, avg_tenor: 0.1),
      ]

      shifts = described_class.new(turns, threshold: 0.15).detect_significant_shifts

      expect(shifts[0][:direction]).to eq("more formal")
      expect(shifts[1][:direction]).to eq("less formal")
    end

    it "includes speaker, delta, to_tenor in each shift Hash" do
      turns = [
        build_turn(turn_id: 1, speaker: "Alice", avg_tenor: 0.1),
        build_turn(turn_id: 2, speaker: "Bob", avg_tenor: 0.6),
]

      shift = described_class.new(turns, threshold: 0.15).detect_significant_shifts.first

      expect(shift[:speaker]).to eq("Bob")
      expect(shift[:to_tenor]).to eq(0.6)
      expect(shift[:delta]).to be_within(1e-9).of(0.5)
    end

    it "does not recompute shifts already present (skips calculate_shifts when no nil/turn_id>1 combo remains)" do
      turns = [build_turn(turn_id: 1, avg_tenor: 0.1), build_turn(turn_id: 2, avg_tenor: 0.9, tenor_shift: 0.0)]
      tracker = described_class.new(turns, threshold: 0.15)

      shifts = tracker.detect_significant_shifts

      # tenor_shift was pre-set to 0.0 (below threshold) and is left untouched — proves
      # calculate_shifts did NOT re-run and overwrite it with the real 0.8 delta.
      expect(shifts).to be_empty
      expect(turns[1].tenor_shift).to eq(0.0)
    end

    it "finds the true immediately-preceding turn by array position, not by turn_id arithmetic, " \
      "when turn_id has gaps" do
      # turn_id 1 and 3 only — array positions are [0]=turn_id 1, [1]=turn_id 3.
      # The old buggy lookup (turns[turn_id - 2]) would resolve turn_id 3's "from" as
      # turns[1] (itself, avg_tenor 0.9) instead of the true predecessor turns[0] (avg_tenor 0.1).
      turns = [build_turn(turn_id: 1, avg_tenor: 0.1), build_turn(turn_id: 3, avg_tenor: 0.9)]

      shift = described_class.new(turns, threshold: 0.15).detect_significant_shifts.first

      expect(shift[:from_tenor]).to eq(0.1)
    end

    it "finds the true immediately-preceding turn by array position when turns are reverse-ordered " \
      "(turn_id descending through the array)" do
      # array order is turn_id 3 then turn_id 1 — turn_id arithmetic (turns[turn_id - 2]) would be
      # nonsensical here (turns[-1] for turn_id 1, turns[1] for turn_id 3); array adjacency must win.
      turns = [build_turn(turn_id: 3, avg_tenor: 0.1), build_turn(turn_id: 1, avg_tenor: 0.9)]

      shift = described_class.new(turns, threshold: 0.15).detect_significant_shifts.first

      expect(shift[:turn_id]).to eq(1)
      expect(shift[:from_tenor]).to eq(0.1)
    end
  end
end
