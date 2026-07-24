# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::TenorTracker do
  describe "#calculate_shifts" do
    it "leaves the first turn's tenor_shift nil (no predecessor to diff against)" do
      turns = [build_turn(turn_id: 1, avg_tenor: 0.4), build_turn(turn_id: 2, avg_tenor: 0.6)]

      described_class.new(turns).calculate_shifts

      expect(turns.first.tenor_shift).to be_nil
    end

    it "sets each subsequent turn's tenor_shift to the delta from the previous turn's avg_tenor" do
      turns = [
        build_turn(turn_id: 1, avg_tenor: 0.4),
        build_turn(turn_id: 2, avg_tenor: 0.6),
        build_turn(turn_id: 3, avg_tenor: 0.5),
]

      described_class.new(turns).calculate_shifts

      expect(turns[1].tenor_shift).to be_within(1e-9).of(0.2)
      expect(turns[2].tenor_shift).to be_within(1e-9).of(-0.1)
    end

    it "mutates the turns array in place" do
      turns = [build_turn(turn_id: 1, avg_tenor: 0.4), build_turn(turn_id: 2, avg_tenor: 0.6)]
      tracker = described_class.new(turns)

      tracker.calculate_shifts

      expect(tracker.turns[1].tenor_shift).to be_within(1e-9).of(0.2)
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

    # Pins today's F5 quirk (a separate later card bullet fixes this, not this slice): from_tenor
    # is looked up via turns[turn.turn_id - 2] — a position-dependent index into the CURRENT
    # turns array, not a turn_id-keyed lookup. When turn_id doesn't line up with array position
    # (e.g. turns filtered/reordered upstream) from_tenor silently resolves to the wrong turn.
    it "F5 quirk: from_tenor is looked up by turns[turn_id - 2] position, not by matching turn_id" do
      # turn_id 1 and 3 only — array positions are [0]=turn_id 1, [1]=turn_id 3.
      turns = [build_turn(turn_id: 1, avg_tenor: 0.1), build_turn(turn_id: 3, avg_tenor: 0.9)]

      shift = described_class.new(turns, threshold: 0.15).detect_significant_shifts.first

      # turn_id - 2 == 1, so it indexes turns[1] (the turn itself, avg_tenor 0.9) as "from_tenor"
      # instead of the true predecessor turns[0] (avg_tenor 0.1) — the quirk, pinned faithfully.
      expect(shift[:from_tenor]).to eq(0.9)
    end
  end
end
