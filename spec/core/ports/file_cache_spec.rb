# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe SFL::Core::Ports::FileCache do
  def build_clause(id: "ann-1", text: "It works.")
    SFL::Core::Types::AnnotatedClause.new(
      id:, text:, syntactic: build_syntactic(text), ideational: build_ideational, interpersonal: build_interpersonal,
      document_id: "doc-1", compiled_at: Time.now.round(0)
    )
  end

  def build_syntactic(text)
    SFL::Core::Types::SyntacticClause.new(
      id: "c-1", text:, tokens: [], root_index: 0, sentence_index: 0, document_id: "doc-1"
    )
  end

  def build_ideational
    SFL::Core::Types::IdeationalPayload.new(
      clause_id: "c-1", process_type: "material", participants: [], circumstances: [], raw_transitivity: {}
    )
  end

  def build_interpersonal
    SFL::Core::Types::InterpersonalPayload.new(
      clause_id: "c-1", mood: "declarative", modality_weight: 0.5, tenor: 0.5,
      speaker_attitude: nil, reasoning: nil, annotation_source: "llm"
    )
  end

  let(:cache_dir) { Dir.mktmpdir }
  let(:cache) { described_class.new(cache_dir:) }

  after { FileUtils.remove_entry(cache_dir) }

  it "creates the cache_dir if it does not already exist" do
    nested = File.join(cache_dir, "nested", "cache")
    described_class.new(cache_dir: nested)
    expect(File.directory?(nested)).to be(true)
  end

  it "round trips a write through #partition as a hit, with the same value" do
    clause = build_clause
    cache.write("key-1", clause)

    hits, misses = cache.partition(["key-1"])

    expect(misses).to eq([])
    expect(hits.fetch("key-1")).to eq(clause)
  end

  it "reports an unwritten key as a miss" do
    hits, misses = cache.partition(["nope"])

    expect(hits).to eq({})
    expect(misses).to eq(["nope"])
  end

  it "treats a corrupted cache file as a miss rather than raising" do
    cache.write("key-1", build_clause)
    File.write(File.join(cache_dir, "key-1.json"), "{not valid json")

    hits, misses = cache.partition(["key-1"])

    expect(hits).to eq({})
    expect(misses).to eq(["key-1"])
  end

  it "treats a structurally malformed (but syntactically valid) cache file as a miss" do
    cache.write("key-1", build_clause)
    File.write(File.join(cache_dir, "key-1.json"), JSON.generate({ unexpected: "shape" }))

    hits, misses = cache.partition(["key-1"])

    expect(hits).to eq({})
    expect(misses).to eq(["key-1"])
  end

  it "reads each key from disk exactly once per #partition call (no double read)" do
    cache.write("key-1", build_clause)
    allow(File).to receive(:read).and_call_original

    hits, = cache.partition(["key-1"])

    expect(hits.key?("key-1")).to be(true)
    expect(File).to have_received(:read).with(File.join(cache_dir, "key-1.json")).once
  end

  it "partitions a mix of hit and miss keys in one call" do
    clause = build_clause
    cache.write("hit", clause)

    hits, misses = cache.partition(%w[hit miss])

    expect(hits.keys).to eq(["hit"])
    expect(misses).to eq(["miss"])
  end
end
