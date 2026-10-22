# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe SFL::Core::Loaders::TranscriptionSource do
  let(:fixtures) { "spec/fixtures/loaders/transcriptions" }
  let(:path) { "#{fixtures}/spoken.txt" }
  let(:ref) { file_ref(path) }
  let(:file_id) { SFL::Core::Loaders::FileId.call(ref) }
  let(:loader) { described_class.new(ref) }

  # The fixture's non-blank lines, stripped, in file order — deliberate
  # markup-looking lines included (STRIDE tampering: content is data).
  let(:expected_lines) do
    [
      "Hello, this is a test of the dictation pipeline.",
      "```ruby",
      'puts "this line is data, not code"',
      "```",
      "# this line looks like a markdown heading",
      "[Speaker 1] hello there",
      "Visit https://example.com/docs for more.",
      "wrapped in leading and trailing whitespace",
  ]
  end

  it "is a Loaders::Source" do
    expect(loader).to be_a(SFL::Core::Loaders::Source)
  end

  it "defines the speaker once as a class constant" do
    expect(described_class::SPEAKER).to eq("User")
  end

  it "returns an Enumerator when no block is given" do
    expect(loader.each_unit).to be_a(Enumerator)
  end

  it "yields exactly one Unit per non-blank line, stripped" do
    units = loader.units

    expect(units).to all(be_a(SFL::Core::Types::Unit))
    expect(units.map(&:text)).to eq(expected_lines)
    expect(units.map(&:text)).to all(match(/\S/))
  end

  it "emits markup-, fence- and URL-looking lines verbatim, never parsed" do
    expect(loader.units.map(&:text)).to include("```ruby", "# this line looks like a markdown heading",
      "[Speaker 1] hello there", "Visit https://example.com/docs for more.")
  end

  it "skips blank and whitespace-only lines without a turn and without a warning" do
    expect { loader.units }.not_to output.to_stderr

    expect(loader.units.map(&:text)).to eq(expected_lines)
  end

  it "numbers turn section ids contiguously over emitted turns only" do
    section_ids = loader.units.map(&:section_id)

    expect(section_ids).to eq(expected_lines.each_with_index.map { |_, i| "#{file_id}#turn-#{i}" })
  end

  it "gives every turn the User speaker with is_user true and no parent" do
    units = loader.units

    expect(units.map(&:speaker).uniq).to eq(["User"])
    expect(units.map(&:is_user).uniq).to eq([true])
    expect(units.map(&:parent_section_id).uniq).to eq([nil])
  end

  it "takes sent_at from the ref's mtime" do
    expect(loader.units.map(&:sent_at).uniq).to eq([ref.mtime])
  end

  it "falls back to the load time when the ref has no mtime (git-tree shape)" do
    mtimeless = SFL::Core::Refs::FileRef.new(
      name: ref.name, extension: ref.extension, content_identity: ref.content_identity,
      size_bytes: ref.size_bytes, mtime: nil, source_id: ref.source_id, path_hint: ref.path_hint
    )

    expect(described_class.new(mtimeless).units.first.sent_at).to be_within(2).of(Time.now)
  end

  it "keys the document the way SubtitleSource's units do" do
    unit = loader.units.first

    expect(unit.document_key).to eq(File.expand_path(path))
    expect(unit.source_path).to eq(File.expand_path(path))
    expect(unit.heading).to be_nil
    expect(unit.metadata).to include("file_id" => file_id)
  end

  it "honours an explicit file_id over the derived one" do
    expect(described_class.new(ref, file_id: "custom").units.first.section_id).to eq("custom#turn-0")
  end

  it "raises Loaders::Error naming the file and extension for a non-.txt ref" do
    Tempfile.create(["spoken", ".xyz"]) do |f|
      f.write("hello\n")
      f.flush
      bad = described_class.new(file_ref(f.path))

      expect { bad.units }.to raise_error(SFL::Core::Loaders::Error, /\.xyz/)
    end
  end

  it "raises Loaders::Error naming the file for a zero-byte transcription file" do
    Tempfile.create(["transcription", ".txt"]) do |f|
      f.flush
      empty = described_class.new(file_ref(f.path))

      expect { empty.units }.to raise_error(SFL::Core::Loaders::Error, /\.txt/)
    end
  end

  it "raises Loaders::Error naming the file for a blank-only transcription file" do
    blank = described_class.new(file_ref("#{fixtures}/blank_only.txt"))

    expect { blank.units }.to raise_error(SFL::Core::Loaders::Error, /blank_only\.txt/)
  end

  # Analysis::Engine's optional review hook: a transcription enqueues through
  # the ingest-review queue on dispatch failure, never through the
  # audio-modality review queue — the hook must contribute nothing (nil,
  # never an entry and never an exception).
  it "contributes no review entry through the shared Source duck contract" do
    expect(loader.review_entry(unit: nil, clauses: [])).to be_nil
  end

  # Analysis::Engine's optional metadata hook: exactly the empty mapping —
  # not nil, not a superclass fallback, never an exception.
  it "adds no extra metadata beyond the common fields Engine builds" do
    expect(loader.extra_metadata([])).to eq({})
  end
end
