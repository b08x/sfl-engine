# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe SFL::Core::Loaders::SubtitleSource do
  let(:fixtures) { "spec/fixtures/loaders/subtitles" }

  it "is a Loaders::Source" do
    expect(described_class.new(file_ref("#{fixtures}/simple.srt"))).to be_a(SFL::Core::Loaders::Source)
  end

  describe "SRT" do
    it "merges cues into synthetic-speaker turns (SRT carries no speaker info)" do
      units = described_class.new(file_ref("#{fixtures}/simple.srt")).units

      expect(units).to all(be_a(SFL::Core::Types::Unit))
      expect(units.map(&:speaker).uniq).to eq(["Speaker"])
    end

    def srt_units(*cue_texts)
      body = cue_texts.each_with_index.map do |text, i|
        "#{i + 1}\n00:00:#{format('%02d', i)},000 --> 00:00:#{format('%02d', i + 1)},000\n#{text}\n"
      end.join("\n")
      Tempfile.create(["labels", ".srt"]) do |f|
        f.write(body)
        f.flush
        return described_class.new(file_ref(f.path)).units
      end
    end

    it "extracts the speaker label from a leading [Speaker N (X)] prefix and strips it from the text" do
      units = described_class.new(file_ref("#{fixtures}/speaker_labels.srt")).units

      expect(units.map(&:speaker)).to eq(["Speaker 1 (M)", "Speaker 2 (F)"])
      expect(units.first.text).to start_with("System initialization complete. Listen up")
      expect(units.first.text).not_to include("[Speaker")
    end

    it "accepts a label without a parenthesized group" do
      units = srt_units("[Speaker 3] Hello there.")

      expect(units.map(&:speaker)).to eq(["Speaker 3"])
      expect(units.first.text).to eq("Hello there.")
    end

    it "matches the label against the multi-line joined cue text" do
      units = srt_units("[Speaker 1 (M)]\nHello there.")

      expect(units.map(&:speaker)).to eq(["Speaker 1 (M)"])
      expect(units.first.text).to eq("Hello there.")
    end

    it "leaves other bracketed text such as [music] in the cue text with no speaker" do
      units = srt_units("[music] Intro theme.", "[applause]")

      expect(units.map(&:speaker)).to eq(["Speaker"])
      expect(units.first.text).to eq("[music] Intro theme. [applause]")
    end

    it "only treats a leading label as a speaker" do
      units = srt_units("He said [Speaker 1] aloud.")

      expect(units.map(&:speaker)).to eq(["Speaker"])
      expect(units.first.text).to eq("He said [Speaker 1] aloud.")
    end

    it "merges consecutive same-speaker cues and splits turns when speakers alternate" do
      units = srt_units(
        "[Speaker 1 (M)] One.", "[Speaker 1 (M)] Two.", "[Speaker 2 (F)] Three.", "[Speaker 1 (M)] Four."
      )

      expect(units.map(&:speaker)).to eq(["Speaker 1 (M)", "Speaker 2 (F)", "Speaker 1 (M)"])
      expect(units.map(&:text)).to eq(["One. Two.", "Three.", "Four."])
    end

    it "raises Loaders::Error when the file has no parseable cues" do
      expect { described_class.new(file_ref("#{fixtures}/empty.srt")).units }.to raise_error(SFL::Core::Loaders::Error)
    end

    it "skips malformed cues without raising" do
      expect { described_class.new(file_ref("#{fixtures}/malformed.srt")).units }.not_to raise_error
    end
  end

  describe "VTT" do
    it "recovers per-cue speakers from <v> voice tags" do
      units = described_class.new(file_ref("#{fixtures}/simple.vtt")).units

      expect(units.map(&:speaker)).to include("Roger Bingham")
    end

    it "falls back to a single synthetic-speaker turn when no voice tags are present" do
      units = described_class.new(file_ref("#{fixtures}/no_voice_tags.vtt")).units

      expect(units.map(&:speaker).uniq).to eq(["Speaker"])
    end
  end

  describe "ASS" do
    it "merges consecutive same-Name Dialogue lines into one turn per speaker change" do
      units = described_class.new(file_ref("#{fixtures}/karaoke.ass")).units

      expect(units.map(&:speaker)).to eq(%w[A B])
    end
  end

  it "raises Loaders::Error for an unsupported extension" do
    Tempfile.create(["subtitle", ".xyz"]) do |f|
      f.write("garbage")
      f.flush
      expect { described_class.new(file_ref(f.path)).units }.to raise_error(SFL::Core::Loaders::Error)
    end
  end

  it "gives turns no parent and keys them by the file path (fact 14)" do
    units = described_class.new(file_ref("spec/fixtures/loaders/subtitles/speaker_labels.srt")).units

    expect(units.map(&:parent_section_id).uniq).to eq([nil])
    expect(units.map(&:document_key).uniq).to eq([File.expand_path("spec/fixtures/loaders/subtitles/speaker_labels.srt")])
  end
end
