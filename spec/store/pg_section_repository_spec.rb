# frozen_string_literal: true

require "spec_helper"

# Fact 12: one row per section with document, unique id, optional parent,
# ordinal, kind, label, level and clause count.
RSpec.describe SFL::Store::PgSectionRepository do
  subject(:repo) { described_class.new(db) }

  let(:db) { SFL::Store::StoreTestDb.db }
  let(:doc) do
    collection_id = SFL::Store::PgCollectionRepository.new(db).find_or_create("c")[:id]
    SFL::Store::PgDocumentRepository.new(db).upsert(collection_id:, document_key: "k")[:id]
  end

  before { SFL::Store::StoreTestDb.clean! }

  def add(id, ordinal, parent = nil, **fields)
    repo.upsert(doc, id, ordinal:, kind: "heading", parent_section_id: parent, **fields)
  end

  it "stores a section with all its fields, once per section id" do
    add("k#a", 1, label: "A", level: 1, clause_count: 4)
    add("k#a", 1, label: "A2", level: 1, clause_count: 5)

    expect(db[:sections].where(section_id: "k#a").all).to contain_exactly(
      hash_including(ordinal: 1, kind: "heading", label: "A2", level: 1, clause_count: 5, parent_section_id: nil)
    )
  end

  it "stores a section at the top level when its parent is not stored" do
    add("k#b", 1, "k#missing")

    expect(db[:sections].where(section_id: "k#b").get(:parent_section_id)).to be_nil
  end

  it "builds the nested tree and lists children in ordinal order" do
    add("k#a", 1)
    add("k#a1", 2, "k#a")
    add("k#a1x", 3, "k#a1")
    add("k#a2", 4, "k#a")
    add("k#b", 5)

    tree = repo.tree(doc)
    expect(tree.map { |node| node[:section_id] }).to eq(%w[k#a k#b])
    expect(tree.first[:children].map { |node| node[:section_id] }).to eq(%w[k#a1 k#a2])
    expect(tree.first[:children].first[:children].map { |node| node[:section_id] }).to eq(%w[k#a1x])
    expect(repo.children("k#a").map { |row| row[:section_id] }).to eq(%w[k#a1 k#a2])
  end

  it "replaces a document's sections and their clauses, keeping the named ones" do
    add("k#old", 1)
    add("k#keep", 2)
    db[:clauses].insert(external_id: "c1", text: "t", section_id: "k#old", sentence_index: 0, root_index: 0)
    db[:clauses].insert(external_id: "c2", text: "t", section_id: "k#keep", sentence_index: 0, root_index: 0)

    expect(repo.replace_for_document(doc, keep: ["k#keep"])).to eq(1)
    expect(db[:sections].select_map(:section_id)).to eq(["k#keep"])
    expect(db[:clauses].select_map(:external_id)).to eq(["c2"])
  end

  it "refuses to move a section to another document and leaves the row as it was" do
    add("k#a", 1, label: "A")
    collection_id = db[:collections].get(:id)
    other = SFL::Store::PgDocumentRepository.new(db).upsert(collection_id:, document_key: "other")[:id]

    expect { repo.upsert(other, "k#a", ordinal: 9, kind: "heading", label: "B") }
      .to raise_error(SFL::Core::Ports::SectionRegistry::ConflictError, /k#a/)
    expect(db[:sections].where(section_id: "k#a").get(%i[document_id label])).to eq([doc, "A"])
  end

  it "orders the tree and children by ordinal, not by insertion order, and returns arrays" do
    add("k#b", 5)
    add("k#a", 1)
    add("k#a2", 4, "k#a")
    add("k#a1", 2, "k#a")

    tree = repo.tree(doc)
    expect(tree.map { |node| node[:section_id] }).to eq(%w[k#a k#b])
    expect(tree.first[:children].map { |node| node[:section_id] }).to eq(%w[k#a1 k#a2])
    children = repo.children("k#a")
    expect(children).to be_an(Array)
    expect(children.map { |row| row[:section_id] }).to eq(%w[k#a1 k#a2])
  end

  # The (document_id, ordinal) index returns rows in ordinal order on its own;
  # with index scans off the rows come back in insertion order, so only the
  # query's ORDER BY can put the tree in ordinal order.
  it "orders the tree by ordinal when the planner does not use the ordinal index" do
    db.transaction do
      db.run("SET LOCAL enable_indexscan = off")
      db.run("SET LOCAL enable_indexonlyscan = off")
      add("k#b", 5)
      add("k#a", 1)

      expect(repo.tree(doc).map { |node| node[:section_id] }).to eq(%w[k#a k#b])
    end
  end

  it "drops a parent that is not stored even when other sections are stored" do
    add("k#a", 1)
    add("k#b", 2, "k#missing")

    expect(db[:sections].where(section_id: "k#b").get(:parent_section_id)).to be_nil
  end

  describe "with a second document" do
    let(:other) do
      SFL::Store::PgDocumentRepository.new(db).upsert(collection_id: db[:collections].get(:id), document_key: "o")[:id]
    end

    before do
      add("k#a", 1)
      repo.upsert(other, "o#a", ordinal: 1, kind: "block")
    end

    it "replaces every section of one document when keep is omitted and leaves the other document's" do
      expect(repo.replace_for_document(doc)).to eq(1)
      expect(db[:sections].select_map(:section_id)).to eq(["o#a"])
    end

    it "builds the tree from one document's sections only" do
      expect(repo.tree(doc).map { |node| node[:section_id] }).to eq(["k#a"])
    end
  end

  it "ignores fields that are not section columns" do
    add("k#a", 1, text: "not a column")

    expect(db[:sections].where(section_id: "k#a").get(:ordinal)).to eq(1)
  end

  it "sets updated_at when it updates a section" do
    add("k#a", 1)
    stale = Time.now - 3600
    db[:sections].where(section_id: "k#a").update(updated_at: stale)
    add("k#a", 1)

    expect(db[:sections].where(section_id: "k#a").get(:updated_at)).to be > stale
  end

  it "names the document_key that owns a section, or nil" do
    add("k#a", 1)

    expect([repo.owner_key("k#a"), repo.owner_key("k#none")]).to eq(["k", nil])
  end
end
