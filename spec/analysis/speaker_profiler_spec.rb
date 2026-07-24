# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::SpeakerProfiler do
  describe "#build_profile" do
    it "raises ArgumentError when given no turns" do
      expect { described_class.new([]).build_profile }.to raise_error(ArgumentError, "No turns provided")
    end

    it "derives speaker_name from the first turn" do
      turns = [build_turn(speaker: "Alice", avg_tenor: 0.4), build_turn(speaker: "Alice", avg_tenor: 0.6)]

      profile = described_class.new(turns).build_profile

      expect(profile.speaker_name).to eq("Alice")
      expect(profile.turn_count).to eq(2)
    end

    it "computes avg_tenor/avg_modality as the mean across turns and tenor_range as [min, max]" do
      turns = [build_turn(avg_tenor: 0.2, avg_modality: 0.3), build_turn(avg_tenor: 0.8, avg_modality: 0.7)]

      profile = described_class.new(turns).build_profile

      expect(profile.avg_tenor).to eq(0.5)
      expect(profile.avg_modality).to eq(0.5)
      expect(profile.tenor_range).to eq([0.2, 0.8])
    end

    it "computes mood_distribution as a rounded fraction of turns per dominant_mood" do
      turns = [
        build_turn(dominant_mood: "declarative"),
        build_turn(dominant_mood: "declarative"),
        build_turn(dominant_mood: "interrogative"),
      ]

      profile = described_class.new(turns).build_profile

      expect(profile.mood_distribution).to eq({ "declarative" => 0.667, "interrogative" => 0.333 })
    end

    it "aggregates dominant_processes by summing each turn's process_types counts" do
      turns = [
        build_turn(process_types: { "material" => 2, "mental" => 1 }),
        build_turn(process_types: { "material" => 1 }),
      ]

      profile = described_class.new(turns).build_profile

      expect(profile.dominant_processes).to eq({ "material" => 3, "mental" => 1 })
    end

    it "returns zero variance when there is only a single turn (values.count < 2 guard)" do
      profile = described_class.new([build_turn(avg_tenor: 0.7)]).build_profile

      expect(profile.tenor_variance).to eq(0.0)
    end

    it "computes a non-zero variance across two or more distinct tenor values" do
      turns = [build_turn(avg_tenor: 0.2), build_turn(avg_tenor: 0.8)]

      profile = described_class.new(turns).build_profile

      # mean = 0.5, sum_squares = 0.09 + 0.09 = 0.18, variance = 0.18 / 2 = 0.09
      expect(profile.tenor_variance).to eq(0.09)
    end
  end

  describe ".build_profiles" do
    it "groups turns by speaker and builds one profile per speaker" do
      turns = [
        build_turn(speaker: "Alice", avg_tenor: 0.4),
        build_turn(speaker: "Bob", avg_tenor: 0.6),
        build_turn(speaker: "Alice", avg_tenor: 0.8),
      ]

      profiles = described_class.build_profiles(turns)

      expect(profiles.keys).to contain_exactly("Alice", "Bob")
      expect(profiles["Alice"].turn_count).to eq(2)
      expect(profiles["Bob"].turn_count).to eq(1)
    end
  end
end
