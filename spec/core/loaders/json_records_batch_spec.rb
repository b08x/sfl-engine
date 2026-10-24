# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe SFL::Core::Loaders::JsonRecordsBatch do
  let(:dir) { Dir.mktmpdir }
  let(:logger) { instance_spy(SFL::Core::Ports::Logger) }
  let(:written) { [] }
  let(:reconciled) { [] }
  let(:removed) { 0 }
  let(:registry) do
    Class.new do
      def initialize(sink, reconciled, removed)
        @sink = sink
        @reconciled = reconciled
        @removed = removed
        @ids = Hash.new { |hash, key| hash[key] = [] }
      end

      # Rolls the sink back to its size at entry when the block raises, as a database transaction does.
      def transaction
        mark = @sink.size
        yield
      rescue
        @sink.slice!(mark..)
        raise
      end

      def register(unit, _count)
        @sink << unit
        @ids[unit.document_key] << unit.section_id
      end

      def written = @ids

      def reconcile(by_document)
        @reconciled << by_document
        @removed
      end
    end
  end
  let(:batch) { described_class.new(registry_factory: -> { registry.new(written, reconciled, removed) }, logger:) }

  after { FileUtils.remove_entry(dir) }

  def msg(text) = { "sender" => "human", "text" => text }
  def convo(uuid, *messages) = { "uuid" => uuid, "chat_messages" => messages }

  def file(name, content)
    path = File.join(dir, name)
    File.write(path, content.is_a?(String) ? content : JSON.generate(content))
    file_ref(path)
  end

  it "ingests intact files and reports the summary shape" do
    summary = batch.call([file("a.json", [convo("c-alpha", msg("one"))])])

    expect(summary).to eq(ingested: 1, processed: 1, failed: [], redundant: [], skipped: [], stale_removed: 0)
    expect(written.map(&:section_id)).to eq(["c-alpha#turn-0"])
  end

  context "when reconciliation removes sections" do
    let(:removed) { 3 }

    it "reports the sections the registry removed as stale_removed" do
      summary = batch.call([file("a.json", [convo("c-alpha", msg("one"))])])

      expect(summary[:stale_removed]).to eq(3)
    end
  end

  describe "reconciliation" do
    it "reconciles each intact document once, with the section ids the run wrote for it" do
      refs = [
        file("a.json", [convo("c-alpha", msg("one"), msg("two")), convo("c-beta", msg("three"))]),
        file("b.json", [convo("c-gamma", msg("four"))]),
      ]
      batch.call(refs)

      expect(reconciled).to eq([
{
  "c-alpha" => ["c-alpha#turn-0", "c-alpha#turn-1"],
  "c-beta" => ["c-beta#turn-0"],
  "c-gamma" => ["c-gamma#turn-0"],
},
])
    end

    it "reconciles a document of an intact file with an empty id list when none of its messages is written" do
      batch.call([file("a.json", [convo("c-alpha")])])

      expect(reconciled).to eq([{ "c-alpha" => [] }])
    end

    it "does not reconcile a document named by a failed file, and reconciles the intact documents" do
      refs = [
        file("b.json", %([{"uuid": "c-beta", "chat_messages": [{"text": "x"}]}, {"uuid": "c-gamma", "chat_m)),
        file("a.json", [convo("c-alpha", msg("one"))]),
      ]
      batch.call(refs)

      expect(reconciled).to eq([{ "c-alpha" => ["c-alpha#turn-0"] }])
    end

    it "does not reconcile a document that a failed file shares with an intact file" do
      refs = [
        file("b.json", %([{"uuid": "c-alpha", "chat_messages": [{"text": "one"}]}, {"uuid": "c-omega", "chat_m)),
        file("a.json", [convo("c-alpha", msg("one"), msg("two")), convo("c-beta", msg("three"))]),
      ]
      batch.call(refs)

      expect(reconciled).to eq([{ "c-beta" => ["c-beta#turn-0"] }])
    end

    it "still reconciles a document of a redundant file, through the intact file that holds it" do
      refs = [
        file("b.json", %([{"uuid": "c-alpha", "chat_messages": [{"text": "one"}]}, {"uuid": "c-beta", "chat_m)),
        file("a.json", [convo("c-alpha", msg("one")), convo("c-beta", msg("three"))]),
      ]
      batch.call(refs)

      expect(reconciled).to eq([{ "c-alpha" => ["c-alpha#turn-0"], "c-beta" => ["c-beta#turn-0"] }])
    end

    it "does not reconcile when no file is intact" do
      summary = batch.call([file("t.json", %([{"uuid": "c-alpha", "chat_messages": [{"text": "one"}]}, {"uu))])

      expect(reconciled).to be_empty
      expect(summary[:stale_removed]).to eq(0)
    end

    it "does not reconcile a repeated uuid's document twice" do
      batch.call([file("a.json", [convo("c-alpha", msg("one")), convo("c-alpha", msg("two"))])])

      expect(reconciled.size).to eq(1)
      expect(reconciled.first.keys).to eq(["c-alpha"])
    end
  end

  it "lists a file with a unique truncated uuid as failed and keeps none of its units" do
    refs = [
      file("b.json", %([{"uuid": "c-beta", "chat_messages": [{"text": "x"}]}, {"uuid": "c-gamma", "chat_m)),
      file("a.json", [convo("c-alpha", msg("one"))]),
]
    summary = batch.call(refs)

    expect(summary[:failed]).to eq([{ file: "b.json", byte_offset: File.size(refs.first.path_hint), reason: "truncated" }])
    expect(written.map(&:document_key)).to eq(["c-alpha"])
  end

  it "moves a truncated file whose every uuid is in an intact file to redundant" do
    refs = [
      file("b.json", %([{"uuid": "c-alpha", "chat_messages": [{"text": "one"}]}, {"uuid": "c-beta", "chat_m)),
      file("a.json", [convo("c-alpha", msg("one")), convo("c-beta", msg("three"))]),
]
    summary = batch.call(refs)

    expect(summary[:failed]).to eq([])
    expect(summary[:redundant].map { |entry| entry[:reason] }).to eq(["redundant_with_intact_file"])
    expect(logger).to have_received(:warn).once.with("json file skipped, every uuid is in an intact file", hash_including(reason: "redundant_with_intact_file"))
    expect(written.map(&:document_key).uniq).to eq(%w[c-alpha c-beta])
  end

  it "keeps a truncated file as failed when a record cut off mid-way cannot be read" do
    refs = [
      file("b.json", %([{"uuid": "c-alpha", "chat_messages": [{"text": "one"}]}, {"uu)),
      file("a.json", [convo("c-alpha", msg("one"))]),
]

    expect(batch.call(refs)[:failed].map { |entry| entry[:reason] }).to eq(["truncated"])
  end

  it "lists a file whose top-level value is not an array as failed with reason not_an_array" do
    summary = batch.call([file("c.json", { "conversations" => [convo("c-beta")] })])

    expect(summary[:failed]).to eq([{ file: "c.json", byte_offset: 0, reason: "not_an_array" }])
  end

  it "lists a repeated uuid under skipped, not failed or redundant" do
    summary = batch.call([file("a.json", [convo("c-alpha", msg("one")), convo("c-alpha", msg("two"))])])

    expect(summary).to include(failed: [], redundant: [])
    expect(summary[:skipped]).to eq([{ file: "a.json", record_index: 1, reason: "duplicate_document_key" }])
  end

  it "writes nothing for a file that fails in a single-file run and raises" do
    ref = file("t.json", %([{"uuid": "c-alpha", "chat_messages": [{"text": "one"}]}, {"uu))

    expect { batch.ingest_one(ref) }.to raise_error(SFL::Core::Loaders::Error, /t\.json: truncated/)
    expect(written).to be_empty
  end
end
