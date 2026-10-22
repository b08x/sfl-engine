# frozen_string_literal: true

require "spec_helper"

# Facts 11, 12 and 20: the columns of the documents, sections and runs tables,
# and the case-insensitive uniqueness of collection names (fact 10).
RSpec.describe "migrations 013 to 017" do # rubocop:disable RSpec/DescribeClass -- migrations, not a class
  let(:db) { SFL::Store::StoreTestDb.db }

  def columns(table) = db.schema(table, reload: true).map(&:first)

  before { SFL::Store::StoreTestDb.clean! }

  it "gives documents a collection, unique key, source path, title, source type, section count and ingest time" do
    expect(columns(:documents)).to include(
      :collection_id, :document_key, :source_path, :title, :source_type, :section_count, :ingested_at, :updated_at
    )
    expect(db.indexes(:documents)).to include(documents_document_key_index: hash_including(unique: true))
  end

  it "gives sections a document, unique section id, parent, ordinal, kind, label, level and clause count" do
    expect(columns(:sections)).to include(
      :section_id, :document_id, :parent_section_id, :ordinal, :kind, :label, :level, :clause_count, :updated_at
    )
  end

  it "gives runs the run id key, kind, collection, status, counts, current item, pid and times" do
    expect(columns(:runs)).to include(
      :run_id, :kind, :collection, :status, :total, :done, :failed, :current_item, :pid,
      :started_at, :heartbeat_at, :finished_at
    )
    expect(db.schema(:runs).to_h[:run_id]).to include(primary_key: true)
  end

  it "rejects a second collection whose name differs only in case" do
    db[:collections].insert(name: "Papers")

    expect { db[:collections].insert(name: "papers") }.to raise_error(Sequel::UniqueConstraintViolation)
  end

  it "clears a child's parent when the parent section is deleted" do
    collection_id = db[:collections].insert(name: "c")
    doc = db[:documents].insert(collection_id:, document_key: "k")
    db[:sections].insert(section_id: "k#a", document_id: doc, ordinal: 1, kind: "heading")
    db[:sections].insert(section_id: "k#b", document_id: doc, ordinal: 2, kind: "block", parent_section_id: "k#a")
    db[:sections].where(section_id: "k#a").delete

    expect(db[:sections].where(section_id: "k#b").get(:parent_section_id)).to be_nil
  end
end
