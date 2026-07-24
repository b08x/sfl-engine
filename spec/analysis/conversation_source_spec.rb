# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe SFL::Analysis::ConversationSource do
  describe "#each_unit (JSONL path)" do
    subject(:source) { described_class.new("spec/fixtures/inputs/sample.jsonl") }

    it "yields one Unit per JSONL line, in order" do
      expect(source.units.size).to eq(5)
    end

    it "derives document_id as conversation_id#turn-N (1-indexed)" do
      units = source.units

      expect(units.first.document_id).to eq("sample#turn-1")
      expect(units.last.document_id).to eq("sample#turn-5")
    end

    it "maps mes/name/is_user onto text/speaker/is_user" do
      unit = source.units.first

      expect(unit.text).to eq("Hey, I'm running into a weird issue with the auth flow.")
      expect(unit.speaker).to eq("Alice")
      expect(unit.is_user).to be(true)
    end

    it "parses send_date into sent_at" do
      unit = source.units.first

      expect(unit.sent_at).to be_a(Time)
    end

    it "carries conversation_id in metadata" do
      unit = source.units.first

      expect(unit.metadata).to eq({ "conversation_id" => "sample" })
    end

    it "falls back to Time.now when send_date can't be parsed, without raising" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "bad_date.jsonl")
        File.write(path, %({"name":"Alice","is_user":true,"send_date":"not a date","mes":"hi"}\n))

        unit = described_class.new(path).units.first

        expect(unit.sent_at).to be_a(Time)
        expect(unit.sent_at).to be_within(5).of(Time.now)
      end
    end

    it "skips JSON-parseable lines that lack a mes key (SillyTavern group-chat header) without raising" do
      units = described_class.new("spec/fixtures/inputs/sillytavern_group.jsonl").units

      expect(units.size).to eq(2)
      expect(units.map(&:speaker)).to eq(%w[Alice Bob])
    end

    it "skips syntactically-invalid JSON lines without raising" do
      units = described_class.new("spec/fixtures/inputs/sillytavern_group.jsonl").units

      expect(units.map(&:text)).to eq(["Hi there.", "Hello!"])
    end

    it "raises Core::Loaders::Error with 'No turns found' when every line is unusable" do
      expect { described_class.new("spec/fixtures/inputs/no_valid_turns.jsonl").units }
        .to raise_error(SFL::Core::Loaders::Error, /No turns found/)
    end

    it "raises Core::Loaders::Error for an unsupported file extension" do
      expect { described_class.new("spec/fixtures/inputs/sample.md").units }
        .to raise_error(SFL::Core::Loaders::Error, /Unsupported conversation input format/)
    end

    it "returns an Enumerator when no block is given to each_unit" do
      expect(source.each_unit).to be_an(Enumerator)
    end
  end

  describe "#each_unit (audio-modality delegation)" do
    subject(:source) { described_class.new("spec/fixtures/loaders/subtitles/simple.srt") }

    it "is detected as audio_modality? for .srt/.vtt/.ass extensions" do
      expect(source.audio_modality?).to be(true)
    end

    it "delegates to Core::Loaders::SubtitleSource for .srt input" do
      units = source.units

      expect(units).not_to be_empty
      expect(units.first.document_id).to start_with("simple#turn-")
    end

    it "is not audio_modality? for a .jsonl path" do
      expect(described_class.new("spec/fixtures/inputs/sample.jsonl").audio_modality?).to be(false)
    end
  end

  describe "#review_entry" do
    it "returns nil for a non-audio-modality source regardless of clauses" do
      source = described_class.new("spec/fixtures/inputs/sample.jsonl")
      unit = source.units.first

      expect(source.review_entry(unit:, clauses: [])).to be_nil
    end

    it "returns an audio review Hash for an audio-modality source" do
      source = described_class.new("spec/fixtures/loaders/subtitles/simple.srt")
      unit = source.units.first

      entry = source.review_entry(unit:, clauses: [])

      expect(entry).to eq(
        modality: "audio", reason: "audio_transcript", generated_text: unit.text, source_type: "chat_native"
      )
    end

    it "threads a custom source_type through to the review entry" do
      source = described_class.new("spec/fixtures/loaders/subtitles/simple.srt", source_type: "chat_claude")
      unit = source.units.first

      entry = source.review_entry(unit:, clauses: [])

      expect(entry[:source_type]).to eq("chat_claude")
    end
  end

  describe "#extra_metadata" do
    it "always returns an empty Hash" do
      source = described_class.new("spec/fixtures/inputs/sample.jsonl")

      expect(source.extra_metadata(source.units)).to eq({})
    end
  end
end
