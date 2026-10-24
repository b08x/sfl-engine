# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Records warn calls as hashes of keyword fields.
class PruneRecordingLogger < SFL::Core::Ports::Null::Logger
  attr_reader :warnings

  def initialize
    super
    @warnings = []
  end

  def warn(_message = nil, **fields, &)
    @warnings << fields
  end
end

RSpec.describe SFL::Store::PruneMissingSources do
  subject(:prune) { described_class.new(db, logger:) }

  let(:db) { SFL::Store::StoreTestDb.db }
  let(:logger) { PruneRecordingLogger.new }
  let(:collection_id) { db[:collections].insert(name: "claude-chats") }
  let(:dir) { Dir.mktmpdir("prune-spec") }

  before { SFL::Store::StoreTestDb.clean! }
  after { FileUtils.remove_entry(dir) }

  def seed_document(key, source_path:, archived: false, sections: 1, clauses: 1)
    doc_id = db[:documents].insert(
      collection_id:, document_key: key, source_path:, section_count: sections,
      archived_at: (Time.now if archived)
    )
    sections.times do |s|
      section_id = "#{key}#turn-#{s}"
      db[:sections].insert(section_id:, document_id: doc_id, ordinal: s, kind: "turn")
      clauses.times do |c|
        external_id = "#{section_id}-c#{c}"
        db[:clauses].insert(external_id:, text: "text #{external_id}", section_id:, sentence_index: c, root_index: 0)
        db[:ideational_payloads].insert(clause_id: external_id, process_type: "material")
        db[:interpersonal_payloads].insert(clause_id: external_id, mood: "declarative")
      end
    end
    doc_id
  end

  def present_file = File.join(dir, "present.json").tap { |p| File.write(p, "{}") }

  def missing_file(name) = File.join(dir, name)

  describe "#call" do
    before do
      seed_document("doc-present", source_path: present_file, sections: 2, clauses: 2)
      seed_document("doc-gone", source_path: missing_file("gone.json"), sections: 2, clauses: 2)
      seed_document("doc-gone-archived", source_path: missing_file("gone-archived.json"), archived: true)
    end

    it "deletes a missing unarchived document with its sections and clauses" do
      prune.call

      expect(db[:documents].where(document_key: "doc-gone").count).to eq(0)
      expect(db[:sections].where(section_id: %w[doc-gone#turn-0 doc-gone#turn-1]).count).to eq(0)
      expect(db[:clauses].where(section_id: %w[doc-gone#turn-0 doc-gone#turn-1]).count).to eq(0)
    end

    it "leaves a document whose source exists untouched" do
      before_rows = db[:clauses].where(section_id: %w[doc-present#turn-0 doc-present#turn-1]).select_map(:external_id)
      prune.call

      expect(db[:documents].where(document_key: "doc-present").count).to eq(1)
      expect(db[:clauses].where(section_id: %w[doc-present#turn-0 doc-present#turn-1]).select_map(:external_id))
        .to match_array(before_rows)
    end

    it "keeps an archived document whose source is missing" do
      prune.call

      row = db[:documents].where(document_key: "doc-gone-archived").first
      expect(row[:archived_at]).not_to be_nil
      expect(db[:sections].where(section_id: "doc-gone-archived#turn-0").count).to eq(1)
    end

    it "returns the deleted and kept counts" do
      expect(prune.call).to eq(deleted: 1, kept_archived: 1, kept_unreadable: 0)
    end

    it "changes nothing on a dry run but returns the same counts" do
      snapshot = db[:documents].order(:id).all

      expect(prune.call(dry_run: true)).to eq(deleted: 1, kept_archived: 1, kept_unreadable: 0)
      expect(db[:documents].order(:id).all).to eq(snapshot)
    end

    it "is idempotent" do
      prune.call
      expect(prune.call).to eq(deleted: 0, kept_archived: 1, kept_unreadable: 0)
    end

    it "does not look up the source of an archived document" do
      allow(File).to receive(:stat).and_call_original
      prune.call

      expect(File).not_to have_received(:stat).with(missing_file("gone-archived.json"))
    end

    it "keeps a document archived after the listing (the delete is guarded by archived_at, in one transaction)" do
      id = db[:documents].where(document_key: "doc-gone").get(:id)
      db[:documents].where(id:).update(archived_at: Time.now)
      rows_before = [db[:documents].count, db[:sections].count, db[:clauses].count]

      expect(prune.__send__(:delete_document, id)).to be(false)
      expect([db[:documents].count, db[:sections].count, db[:clauses].count]).to eq(rows_before)
    end

    it "removes no file on disk" do
      File.write(File.join(dir, "keep.txt"), "bytes")
      stamp = File.mtime(File.join(dir, "keep.txt"))
      prune.call

      expect(File.read(File.join(dir, "keep.txt"))).to eq("bytes")
      expect(File.mtime(File.join(dir, "keep.txt"))).to eq(stamp)
      expect(File.exist?(present_file)).to be(true)
    end
  end

  describe "source lookup failures" do
    it "keeps a document whose lookup raises Errno::EACCES and logs source_unreadable" do
      path = missing_file("gone.json")
      seed_document("doc-gone", source_path: path)
      allow(File).to receive(:stat).and_call_original
      allow(File).to receive(:stat).with(path).and_raise(Errno::EACCES)

      result = prune.call

      expect(result).to eq(deleted: 0, kept_archived: 0, kept_unreadable: 1)
      expect(db[:documents].where(document_key: "doc-gone").count).to eq(1)
      expect(logger.warnings).to eq([
{
  component: "PruneMissingSources",
  document_key: "doc-gone",
  reason: "source_unreadable",
},
])
    end

    [Errno::EIO, Errno::ESTALE, Errno::ENOTCONN].each do |error|
      it "keeps a document whose lookup raises #{error}" do
        path = missing_file("gone.json")
        seed_document("doc-gone", source_path: path)
        allow(File).to receive(:stat).and_call_original
        allow(File).to receive(:stat).with(path).and_raise(error)

        prune.call

        expect(db[:documents].where(document_key: "doc-gone").count).to eq(1)
        expect(logger.warnings.map { |w| w[:reason] }).to eq(["source_unreadable"])
      end
    end

    it "keeps a document whose path cannot be checked (ArgumentError) and logs source_unreadable" do
      path = missing_file("bad.json")
      seed_document("doc-bad", source_path: path)
      allow(File).to receive(:stat).and_call_original
      allow(File).to receive(:stat).with(path).and_raise(ArgumentError, "string contains null byte")

      expect(prune.call).to eq(deleted: 0, kept_archived: 0, kept_unreadable: 1)
      expect(logger.warnings.map { |w| w[:reason] }).to eq(["source_unreadable"])
    end
  end

  describe "documents without a usable source path" do
    ["", nil, "   "].each do |path|
      it "keeps a document with source_path #{path.inspect} and warns source_path_missing" do
        seed_document("doc-no-path", source_path: path)

        expect(prune.call).to eq(deleted: 0, kept_archived: 0, kept_unreadable: 1)
        expect(db[:documents].where(document_key: "doc-no-path").count).to eq(1)
        expect(logger.warnings).to eq([
{
  component: "PruneMissingSources",
  document_key: "doc-no-path",
  reason: "source_path_missing",
},
])
      end
    end
  end

  it "writes the document key as one line in a warning" do
    seed_document("doc\nsplit", source_path: nil)
    prune.call

    expect(logger.warnings.first[:document_key]).to eq("doc?split")
  end
end
