# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe SFL::Core::Loaders::SubtitleSource do
  let(:fixtures) { "spec/fixtures/loaders/subtitles" }

  it "is a Loaders::Source" do
    expect(described_class.new("#{fixtures}/simple.srt")).to be_a(SFL::Core::Loaders::Source)
  end

  describe "SRT" do
    it "merges cues into synthetic-speaker turns (SRT carries no speaker info)" do
      units = described_class.new("#{fixtures}/simple.srt").units

      expect(units).to all(be_a(SFL::Core::Types::Unit))
      expect(units.map(&:speaker).uniq).to eq(["Speaker"])
    end

    it "raises Loaders::Error when the file has no parseable cues" do
      expect { described_class.new("#{fixtures}/empty.srt").units }.to raise_error(SFL::Core::Loaders::Error)
    end

    it "skips malformed cues without raising" do
      expect { described_class.new("#{fixtures}/malformed.srt").units }.not_to raise_error
    end
  end

  describe "VTT" do
    it "recovers per-cue speakers from <v> voice tags" do
      units = described_class.new("#{fixtures}/simple.vtt").units

      expect(units.map(&:speaker)).to include("Roger Bingham")
    end

    it "falls back to a single synthetic-speaker turn when no voice tags are present" do
      units = described_class.new("#{fixtures}/no_voice_tags.vtt").units

      expect(units.map(&:speaker).uniq).to eq(["Speaker"])
    end
  end

  describe "ASS" do
    it "merges consecutive same-Name Dialogue lines into one turn per speaker change" do
      units = described_class.new("#{fixtures}/karaoke.ass").units

      expect(units.map(&:speaker)).to eq(%w[A B])
    end
  end

  it "raises Loaders::Error for an unsupported extension" do
    Tempfile.create(["subtitle", ".xyz"]) do |f|
      f.write("garbage")
      f.flush
      expect { described_class.new(f.path).units }.to raise_error(SFL::Core::Loaders::Error)
    end
  end
end
