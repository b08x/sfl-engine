# frozen_string_literal: true

require "spec_helper"

# Fact 11: one row per document, unique key.
RSpec.describe SFL::Store::PgDocumentRepository do
  subject(:repo) { described_class.new(db) }

  let(:db) { SFL::Store::StoreTestDb.db }
  let(:collections) { SFL::Store::PgCollectionRepository.new(db) }
  let(:papers) { collections.find_or_create("papers")[:id] }
  let(:notes) { collections.find_or_create("notes")[:id] }

  before { SFL::Store::StoreTestDb.clean! }

  it "inserts a document with its collection, key, source path, title and source type" do
    row = repo.upsert(collection_id: papers, document_key: "/p/a.md", source_path: "/p/a.md", title: "a.md",
      source_type: "vault_markdown")

    expect(row).to include(collection_id: papers, document_key: "/p/a.md", title: "a.md", section_count: 0)
    expect(row[:ingested_at]).to be_a(Time)
  end

  it "keeps one row per key and updates it in place" do
    first = repo.upsert(collection_id: papers, document_key: "k", title: "old")
    second = repo.upsert(collection_id: notes, document_key: "k", title: "new")

    expect(second).to include(id: first[:id], collection_id: notes, title: "new")
    expect(second[:updated_at]).to be >= first[:updated_at]
    expect(db[:documents].count).to eq(1)
  end

  it "moves a document to another collection and lists by collection" do
    repo.upsert(collection_id: papers, document_key: "k")
    repo.move_to("k", notes)

    expect(repo.list_by_collection(notes).map { |row| row[:document_key] }).to eq(["k"])
    expect(repo.list_by_collection(papers)).to be_empty
  end

  it "recounts sections" do
    doc = repo.upsert(collection_id: papers, document_key: "k")
    SFL::Store::PgSectionRepository.new(db).upsert(doc[:id], "k#a", ordinal: 1, kind: "block")
    repo.refresh_section_count(doc[:id])

    expect(repo.find("k")[:section_count]).to eq(1)
  end
end
