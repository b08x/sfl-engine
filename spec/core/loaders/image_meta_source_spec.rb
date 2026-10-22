# frozen_string_literal: true

require "spec_helper"
require "time"
require "tempfile"

RSpec.describe SFL::Core::Loaders::ImageMetaSource do
  let(:fixtures) { "spec/fixtures/loaders/image_meta" }
  let(:path) { "#{fixtures}/analysis.yaml" }
  let(:ref) { file_ref(path) }
  let(:file_id) { SFL::Core::Loaders::FileId.call(ref) }

  def loader_at(name)
    described_class.new(file_ref("#{fixtures}/#{name}.yaml"))
  end

  it "is a Loaders::Source" do
    expect(described_class.new(ref)).to be_a(SFL::Core::Loaders::Source)
  end

  it "returns an Enumerator when no block is given" do
    expect(described_class.new(ref).each_unit).to be_a(Enumerator)
  end

  it "yields exactly one Unit for a well-formed sidecar" do
    units = described_class.new(ref).units

    expect(units.size).to eq(1)
    expect(units.first).to be_a(SFL::Core::Types::Unit)
  end

  it "maps the well-formed unit field by field" do
    unit = described_class.new(ref).units.first

    expect(unit.section_id).to eq("#{file_id}#meta")
    expect(unit.text).to eq("A whiteboard diagram of the ingest pipeline")
    expect(unit.sent_at).to eq(Time.parse("2025-11-02T14:03:00Z"))
    expect(unit.document_key).to eq(File.expand_path(path))
    expect(unit.source_path).to eq(File.expand_path(path))
    expect(unit.metadata).to include("file_id" => file_id, "model_used" => "gpt-4o", "evaluation" => "good")
    # A document-analysis sidecar is not a speech turn: attribution lives
    # in metadata, never in a fabricated speaker.
    expect(unit).to have_attributes(speaker: nil, is_user: nil, parent_section_id: nil, heading: nil)
  end

  it "leaves metadata sparse when model_used/evaluation are absent" do
    unit = loader_at("sparse").units.first

    expect(unit.metadata).to include("file_id" => SFL::Core::Loaders::FileId.call(file_ref("#{fixtures}/sparse.yaml")))
    expect(unit.metadata).not_to include("model_used", "evaluation")
    expect(unit.text).to eq("Screenshot of a terminal")
  end

  it "degrades to sent_at nil, silently, when the timestamp key is absent" do
    expect { loader_at("no_timestamp").units }.not_to output.to_stderr

    unit = loader_at("no_timestamp").units.first
    expect(unit.sent_at).to be_nil
    expect(unit.text).to eq("No timestamp on this one")
  end

  it "warns once naming the file and value for an unparseable timestamp, then leaves sent_at nil" do
    expect { loader_at("bad_timestamp").units }
      .to output(/not a date at all.*bad_timestamp\.yaml/).to_stderr

    expect(loader_at("bad_timestamp").units.first.sent_at).to be_nil
  end

  it "raises Loaders::Error naming the file when the description key is missing" do
    expect { loader_at("missing_description").units }
      .to raise_error(SFL::Core::Loaders::Error, /missing_description\.yaml/)
  end

  it "raises Loaders::Error naming the file when the description is blank" do
    expect { loader_at("blank_description").units }
      .to raise_error(SFL::Core::Loaders::Error, /blank_description\.yaml/)
  end

  it "raises Loaders::Error for a non-string description, without fabricating inspected text" do
    expect { loader_at("non_string_description").units }.to raise_error(SFL::Core::Loaders::Error) do |error|
      expect(error.message).to include("non_string_description.yaml")
      # No inspected Hash/Array is ever stringified into the unit's text payload.
      expect(error.message).not_to include("nested")
    end
  end

  it "raises Loaders::Error naming the file for unparseable YAML" do
    expect { loader_at("malformed").units }
      .to raise_error(SFL::Core::Loaders::Error, /malformed\.yaml/)
  end

  it "raises Loaders::Error when the parsed root is not a mapping (sequence)" do
    expect { loader_at("root_sequence").units }
      .to raise_error(SFL::Core::Loaders::Error, /root_sequence\.yaml/)
  end

  it "raises Loaders::Error when the parsed root is not a mapping (bare string)" do
    expect { loader_at("root_string").units }
      .to raise_error(SFL::Core::Loaders::Error, /root_string\.yaml/)
  end

  # STRIDE elevation of privilege: !ruby/object tags must be rejected by the
  # safe parser before any Ruby object is instantiated — the error is the
  # safe parser's own rejection wrapped in Loaders::Error, not a
  # NoMethodError raised by calling [] on an instantiated object.
  it "rejects !ruby/object tags without instantiating anything" do
    allow(YAML).to receive(:safe_load).and_call_original

    expect { loader_at("ruby_object").units }.to raise_error(SFL::Core::Loaders::Error) do |error|
      expect(error.message).to include("ruby_object.yaml")
      # The safe parser's own rejection, not a NoMethodError from an
      # instantiated object such as `undefined method [] for OpenStruct`.
      expect(error.message).to include("Tried to load unspecified class")
    end

    expect(YAML).to have_received(:safe_load)
  end

  it "raises Loaders::Error naming the file and extension for a non-.yaml ref" do
    Tempfile.create(["image", ".xyz"]) do |f|
      f.write("description: nope\n")
      f.flush
      bad = described_class.new(file_ref(f.path))

      expect { bad.units }.to raise_error(SFL::Core::Loaders::Error, /\.xyz/)
    end
  end

  it "honours an explicit file_id over the derived one" do
    expect(described_class.new(ref, file_id: "custom").units.first.section_id).to eq("custom#meta")
  end

  # Analysis::Engine's optional review hook: a document-analysis sidecar is
  # not a speech turn — the hook must contribute nothing (nil, never an
  # entry and never an exception).
  it "contributes no review entry through the shared Source duck contract" do
    expect(described_class.new(ref).review_entry(unit: nil, clauses: [])).to be_nil
  end

  # Analysis::Engine's optional metadata hook: exactly the empty mapping —
  # not nil, not a superclass fallback, never an exception.
  it "adds no extra metadata beyond the fields that ride on each unit" do
    expect(described_class.new(ref).extra_metadata([])).to eq({})
  end

  # YAML timestamp scalars are only deserializable because Time is on the
  # safe_load permit list — a bare (unquoted) timestamp must come back as a
  # Time, with no warning, not as a parse rejection.
  it "accepts a bare YAML timestamp scalar, returning the Time it deserializes to" do
    expect { loader_at("time_scalar").units }.not_to output.to_stderr

    unit = loader_at("time_scalar").units.first
    expect(unit.sent_at).to be_a(Time)
    expect(unit.sent_at).to eq(Time.parse("2025-11-02T14:03:00Z"))
    expect(unit.text).to eq("A photo whose timestamp is a bare YAML scalar")
  end

  # The Time fast path must return the deserialized value itself, not a
  # Time re-parsed from its to_s: Time#to_s drops sub-second precision, so
  # re-parsing silently truncates a timestamp that carries nanoseconds.
  it "preserves a bare timestamp's sub-second precision without a to_s round-trip" do
    unit = loader_at("time_nano").units.first

    expect(unit.sent_at).to be_a(Time)
    expect(unit.sent_at).to eq(Time.parse("2025-11-02T14:03:00.123456789+05:30"))
    expect(unit.sent_at.nsec).to eq(123_456_789)
  end

  # A non-string timestamp the parser cannot coerce (an integer here) takes
  # the same degraded path as an unparseable string: one warning, sent_at
  # nil, and the unit still emitted.
  it "degrades to sent_at nil, with one warning, for a non-string timestamp" do
    expect { loader_at("int_timestamp").units }.to output(/2025.*int_timestamp\.yaml/).to_stderr

    unit = loader_at("int_timestamp").units.first
    expect(unit.sent_at).to be_nil
    expect(unit.text).to eq("A photo with a numeric timestamp")
  end

  # The degraded-timestamp warning names the raw value in its inspected
  # form — quotes and all — so an operator can tell a string "123" from an
  # integer 123 in the sidecar.
  it "warns with the value's inspected spelling, not its to_s form" do
    expect { loader_at("bad_timestamp").units }
      .to output(/"not a date at all".*bad_timestamp\.yaml/).to_stderr
  end
end
