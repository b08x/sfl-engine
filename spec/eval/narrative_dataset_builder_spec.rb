# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe SFL::Eval::NarrativeDatasetBuilder do
  let(:client) { instance_spy(SFL::Eval::LangfuseClient) }
  let(:log) { StringIO.new }
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(dir) }

  def turn(id, clauses: 2, defaulted: 0)
    {
      "turn_id" => id,
      "speaker" => "A",
      "preview" => "hi",
      "avg_tenor" => 0.5,
      "avg_modality" => 0.2,
      "dominant_mood" => "declarative",
      "clause_count" => clauses,
      "defaulted_count" => defaulted,
    }
  end

  def write_report(name, turns: Array.new(9) { |i| turn(i + 1) })
    path = File.join(dir, "#{name}.json")
    report = {
      "metadata" => { "conversation_id" => name, "turn_count" => turns.size, "speakers" => %w[A B] },
      "turns" => turns,
    }
    File.write(path, JSON.generate(report))
    path
  end

  def source(number, path, probe: nil)
    described_class::Source.new(item_no: number, path:, source: "s#{number}", genre: "chat", probe:)
  end

  it "upserts the dataset and one item per existing report, skipping absent files" do
    sources = [source(1, write_report("one")), source(11, File.join(dir, "missing.json"))]

    result = described_class.new(client:, sources:, log:).call

    expect(result.loaded).to eq([1])
    expect(result.skipped).to eq([11])
    expect(client).to have_received(:upsert_dataset).with(hash_including(name: "sfl-narrative-digests"))
    expect(client).to have_received(:upsert_dataset_item).once
      .with(hash_including(dataset: "sfl-narrative-digests", id: "nd-1"))
  end

  it "carries the digest text and metadata on the item" do
    item = described_class.new(client:, sources: [], log:).build_item(source(3, write_report("three")))

    expect(item[:id]).to eq("nd-3")
    expect(item[:input][:digest_text]).to include("A")
    expect(item[:metadata]).to include(item_no: 3, genre: "chat", speakers: 2, turns: 9, probe: nil)
  end

  it "adds the LOW CONFIDENCE warning to a :low_confidence probe without touching the file" do
    path = write_report("nine")
    before = File.read(path)

    item = described_class.new(client:, sources: [], log:).build_item(source(9, path, probe: :low_confidence))

    expect(item[:input][:digest_text]).to include("LOW CONFIDENCE WARNING")
    expect(item[:metadata][:probe]).to eq("low_confidence")
    expect(File.read(path)).to eq(before)
  end

  it "marks three rows UNRELIABLE for an :unreliable probe" do
    item = described_class.new(client:, sources: [], log:).build_item(source(10, write_report("ten"), probe: :unreliable))

    expect(item[:input][:digest_text].scan("UNRELIABLE").size).to eq(3)
  end

  it "lists 14 sources, the last four under the eval directory" do
    catalog = SFL::Eval::NarrativeSources.catalog(engine_output: "e", compiler_output: "c", eval_dir: "x")

    expect(catalog.map(&:item_no)).to eq((1..14).to_a)
    expect(catalog.last(4).map(&:path)).to all(start_with("x/nd-"))
  end
end
