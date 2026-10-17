# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe SFL::Analysis::ConversationSource do
  describe "#each_unit (JSONL path)" do
    subject(:source) { described_class.new(file_ref("spec/fixtures/inputs/sample.jsonl")) }

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

        unit = described_class.new(file_ref(path)).units.first

        expect(unit.sent_at).to be_a(Time)
        expect(unit.sent_at).to be_within(5).of(Time.now)
      end
    end

    it "skips JSON-parseable lines that lack a mes key (SillyTavern group-chat header) without raising" do
      units = described_class.new(file_ref("spec/fixtures/inputs/sillytavern_group.jsonl")).units

      expect(units.size).to eq(2)
      expect(units.map(&:speaker)).to eq(%w[Alice Bob])
    end

    it "skips syntactically-invalid JSON lines without raising" do
      units = described_class.new(file_ref("spec/fixtures/inputs/sillytavern_group.jsonl")).units

      expect(units.map(&:text)).to eq(["Hi there.", "Hello!"])
    end

    it "raises Core::Loaders::Error with 'No turns found' when every line is unusable" do
      expect { described_class.new(file_ref("spec/fixtures/inputs/no_valid_turns.jsonl")).units }
        .to raise_error(SFL::Core::Loaders::Error, /No turns found/)
    end

    it "raises Core::Loaders::Error for an unsupported file extension" do
      expect { described_class.new(file_ref("spec/fixtures/inputs/sample.md")).units }
        .to raise_error(SFL::Core::Loaders::Error, /Unsupported conversation input format/)
    end

    it "returns an Enumerator when no block is given to each_unit" do
      expect(source.each_unit).to be_an(Enumerator)
    end
  end

  describe "#each_unit (audio-modality delegation)" do
    subject(:source) { described_class.new(file_ref("spec/fixtures/loaders/subtitles/simple.srt")) }

    it "is detected as audio_modality? for .srt/.vtt/.ass extensions" do
      expect(source.audio_modality?).to be(true)
    end

    it "delegates to Core::Loaders::SubtitleSource for .srt input" do
      units = source.units

      expect(units).not_to be_empty
      expect(units.first.document_id).to start_with("simple#turn-")
    end

    it "is not audio_modality? for a .jsonl path" do
      expect(described_class.new(file_ref("spec/fixtures/inputs/sample.jsonl")).audio_modality?).to be(false)
    end
  end

  describe "subtitle-cue JSONL" do
    subject(:source) { described_class.new(file_ref("spec/fixtures/inputs/subtitle_cues.jsonl")) }

    it "merges adjacent same-speaker cues into one turn and splits on speaker change" do
      units = source.units

      expect(units.map(&:speaker)).to eq(["Speaker 1 (M)", "Speaker 2 (F)"])
      expect(units.first.text).to eq(
        "Systemic consensus locked. Welcome to the deep dive, all you fancy meat sacks out there."
      )
    end

    it "builds subtitle-style document_id, metadata and sent_at" do
      mtime = File.mtime("spec/fixtures/inputs/subtitle_cues.jsonl")
      unit = source.units.first

      expect(unit.document_id).to eq("subtitle_cues#turn-0")
      expect(unit.metadata).to eq({ "file_id" => "subtitle_cues" })
      expect(unit.is_user).to be(false)
      expect(unit.sent_at).to be_within(1.0).of(mtime + 0.56)
    end

    it "is audio_modality and returns an audio review entry" do
      unit = source.units.first

      expect(source.audio_modality?).to be(true)
      expect(source.audio_modality).to be(true)
      expect(source.review_entry(unit:, clauses: [])).to include(modality: "audio", reason: "audio_transcript")
    end

    it "treats a missing or non-numeric start_ms as offset 0 and skips empty text" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "cues.jsonl")
        File.write(path, <<~JSONL)
          {"speaker":"A","text":"  one  ","start_ms":"x"}
          {"speaker":"A","text":"   "}
          {"speaker":"B","text":"two"}
        JSONL

        units = described_class.new(file_ref(path)).units

        expect(units.map(&:text)).to eq(%w[one two])
      end
    end

    describe "start_ms value types" do
      # Cue timestamps are rendered as whole-second ISO 8601 strings, so sent_at is
      # compared in whole seconds. A .7 s mtime fraction makes 0.56 s and 0.0 s differ.
      let(:base) { Time.at(1_700_000_000, 700, :millisecond) }

      def seconds_after_base(*start_values)
        Dir.mktmpdir do |dir|
          path = File.join(dir, "cues.jsonl")
          lines = start_values.each_with_index.map do |value, index|
            JSON.generate({ speaker: "S#{index}", text: "t#{index}", start_ms: value })
          end
          File.write(path, "#{lines.join("\n")}\n")
          File.utime(base, base, path)
          described_class.new(file_ref(path)).units.map { |unit| unit.sent_at.to_i - base.to_i }
        end
      end

      {
        "560" => 0.56,
        "560.5" => 0.5605,
        " 560 " => 0.56,
        560 => 0.56,
        560.5 => 0.5605,
        "x" => 0.0,
        "12abc" => 0.0,
        "" => 0.0,
      }.each do |value, offset|
        it "reads start_ms #{value.inspect} as offset #{offset}" do
          expect(seconds_after_base(value)).to eq([(0.7 + offset).floor])
        end
      end

      it "keeps cue order meaningful for numeric-String start_ms" do
        first, second = seconds_after_base("560", "2200")

        expect(second - first).to be_within(1.0).of(1.64)
        expect(second).to be > first
      end
    end

    it "treats a file mixing shapes as native chat and skips cue-shaped lines" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "mixed.jsonl")
        File.write(path, %({"speaker":"A","text":"cue"}\n{"name":"Al","mes":"hi","send_date":"2024-01-01"}\n))

        source = described_class.new(file_ref(path))

        expect(source.units.map(&:text)).to eq(["hi"])
        expect(source.audio_modality?).to be(false)
      end
    end

    it "keeps native chat JSONL non-audio" do
      expect(described_class.new(file_ref("spec/fixtures/inputs/sample.jsonl")).audio_modality?).to be(false)
    end
  end

  describe "'No turns found' error" do
    it "states line counts, unparseable count and first record keys" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "odd.jsonl")
        File.write(path, %({"b":1,"a":2}\nnot json\n\n))

        expect { described_class.new(file_ref(path)).units }.to raise_error(
          SFL::Core::Loaders::Error,
          /No turns found in odd: read 2 line\(s\), 1 unparseable; first record keys: \["a", "b"\]; expected/
        )
      end
    end

    it "truncates the key list to 12 keys" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "wide.jsonl")
        File.write(path, "#{(1..15).to_h { |i| [format('k%02d', i), i] }.to_json}\n")

        expect { described_class.new(file_ref(path)).units }
          .to raise_error(SFL::Core::Loaders::Error, /k12[^k]*\]/)
      end
    end

    it "still raises with 'No turns found' for an empty file" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "empty.jsonl")
        File.write(path, "")

        expect { described_class.new(file_ref(path)).units }
          .to raise_error(SFL::Core::Loaders::Error, /No turns found in empty/)
      end
    end
  end

  describe "#review_entry" do
    it "returns nil for a non-audio-modality source regardless of clauses" do
      source = described_class.new(file_ref("spec/fixtures/inputs/sample.jsonl"))
      unit = source.units.first

      expect(source.review_entry(unit:, clauses: [])).to be_nil
    end

    it "returns an audio review Hash for an audio-modality source" do
      source = described_class.new(file_ref("spec/fixtures/loaders/subtitles/simple.srt"))
      unit = source.units.first

      entry = source.review_entry(unit:, clauses: [])

      expect(entry).to eq(
        modality: "audio", reason: "audio_transcript", generated_text: unit.text, source_type: "chat_native"
      )
    end

    it "threads a custom source_type through to the review entry" do
      source = described_class.new(file_ref("spec/fixtures/loaders/subtitles/simple.srt"), source_type: "chat_claude")
      unit = source.units.first

      entry = source.review_entry(unit:, clauses: [])

      expect(entry[:source_type]).to eq("chat_claude")
    end
  end

  describe "#extra_metadata" do
    it "always returns an empty Hash" do
      source = described_class.new(file_ref("spec/fixtures/inputs/sample.jsonl"))

      expect(source.extra_metadata(source.units)).to eq({})
    end
  end
end
