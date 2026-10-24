# frozen_string_literal: true

require "spec_helper"

# Facts 8, 12, 13, 14, 16 and 17 against Postgres.
RSpec.describe SFL::Store::PgSectionRegistry do
  let(:db) { SFL::Store::StoreTestDb.db }
  let(:logger) { instance_double(SFL::Core::Ports::Logger, warn: nil, info: nil) }

  before { SFL::Store::StoreTestDb.clean! }

  def registry(collection) = described_class.new(db, collection:, logger:)

  def unit(id, key: "/p/doc.md", **attrs)
    SFL::Core::Types::Unit.new(section_id: id, text: "t", document_key: key, source_path: key, **attrs)
  end

  # Stands in for ClauseStore#replace_section: one clause row per section.
  def store(registry, unit, clauses: 1)
    registry.transaction do
      db[:clauses].where(section_id: unit.section_id).delete
      clauses.times do |i|
        db[:clauses].insert(external_id: "#{unit.section_id}-#{i}-#{rand}", text: "t", section_id: unit.section_id,
          sentence_index: i, root_index: 0)
      end
      registry.register(unit, clauses)
    end
  end

  def collection_of(key) = db[:collections].where(id: db[:documents].where(document_key: key).get(:collection_id)).get(:name)

  it "creates the collection and adds the document to it (fact 8)" do
    store(registry("Papers"), unit("doc#a"))

    expect(collection_of("/p/doc.md")).to eq("Papers")
    expect(db[:documents].first).to include(source_path: "/p/doc.md", title: "doc.md", section_count: 1)
  end

  it "stores nested heading sections with ordinal, label, level and clause count (facts 12, 13)" do
    reg = registry("c")
    store(reg, unit("doc#top", heading: "Top", metadata: { "heading_level" => 1 }), clauses: 2)
    store(reg, unit("doc#sub", heading: "Sub", parent_section_id: "doc#top", metadata: { "heading_level" => 2 }))

    expect(db[:sections].order(:ordinal).select_map(%i[section_id parent_section_id ordinal kind label level clause_count]))
      .to eq([["doc#top", nil, 1, "heading", "Top", 1, 2], ["doc#sub", "doc#top", 2, "heading", "Sub", 2, 1]])
  end

  it "stores turns without a parent, labelled with the speaker (fact 14)" do
    store(registry("c"), unit("chat#turn-1", key: "chat.jsonl", speaker: "Alice"))

    expect(db[:sections].first).to include(parent_section_id: nil, kind: "turn", label: "Alice")
  end

  it "moves a document from another collection with its sections and warns naming both (fact 16)" do
    store(registry("old"), unit("doc#a"))
    store(registry("new"), unit("doc#a"))

    expect(collection_of("/p/doc.md")).to eq("new")
    expect(db[:sections].count).to eq(1)
    expect(logger).to have_received(:warn)
      .with("document moved", document_key: "/p/doc.md", from_collection: "old", to_collection: "new")
  end

  it "updates a re-ingested section in place, keeping its surrogate id, and bumps updated_at (fact 17)" do
    first = registry("c")
    store(first, unit("doc#a"))
    store(first, unit("doc#b"))
    ids = db[:sections].select_hash(:section_id, :id)
    before = db[:documents].get(:updated_at)

    store(registry("c"), unit("doc#a"), clauses: 3)

    expect(db[:sections].select_hash(:section_id, :id)).to eq(ids)
    expect(db[:documents].get(:updated_at)).to be > before
    expect(logger).not_to have_received(:warn)
  end

  it "keeps the surrogate id of every section across a re-ingest of the whole document" do
    store(registry("c"), unit("doc#a"))
    store(registry("c"), unit("doc#b"))
    ids = db[:sections].select_hash(:section_id, :id)

    reg = registry("c")
    store(reg, unit("doc#a"), clauses: 2)
    store(reg, unit("doc#b"), clauses: 2)

    expect(db[:sections].select_hash(:section_id, :id)).to eq(ids)
    expect(db[:sections].order(:ordinal).select_map(%i[section_id ordinal])).to eq([["doc#a", 1], ["doc#b", 2]])
    expect(db[:documents].first).to include(section_count: 2)
  end

  it "removes the section a shrunk document no longer has, with its clauses, keeps the others' ids, and counts the rows (fact 17)" do
    first = registry("c")
    store(first, unit("doc#a"), clauses: 2)
    store(first, unit("doc#b"), clauses: 3)
    store(first, unit("doc#c"), clauses: 1)
    ids = db[:sections].select_hash(:section_id, :id)
    expect([db[:documents].count, db[:sections].count, db[:clauses].count]).to eq([1, 3, 6])

    reg = registry("c")
    store(reg, unit("doc#a"), clauses: 2)
    store(reg, unit("doc#b"), clauses: 3)
    expect(reg.reconcile(reg.written)).to eq(1)

    expect(db[:sections].select_hash(:section_id, :id)).to eq(ids.except("doc#c"))
    expect([db[:documents].count, db[:sections].count, db[:clauses].count]).to eq([1, 2, 5])
    expect(db[:clauses].where(section_id: "doc#c").count).to eq(0)
    expect(db[:documents].get(:section_count)).to eq(2)
  end

  it "replaces a re-ingested section's clauses rather than adding to them" do
    store(registry("c"), unit("doc#a"), clauses: 2)
    store(registry("c"), unit("doc#a"), clauses: 3)
    expect(db[:clauses].where(section_id: "doc#a").count).to eq(3)

    store(registry("c"), unit("doc#a"), clauses: 1)
    expect(db[:clauses].where(section_id: "doc#a").count).to eq(1)
    expect(db[:sections].where(section_id: "doc#a").count).to eq(1)
  end

  it "still refuses another document's section id after the owner is re-ingested" do
    store(registry("alpha"), unit("README#intro", key: "/a/README.md"), clauses: 2)
    id = db[:sections].where(section_id: "README#intro").get(:id)
    store(registry("alpha"), unit("README#intro", key: "/a/README.md"), clauses: 2)

    expect { store(registry("beta"), unit("README#intro", key: "/b/README.md")) }
      .to raise_error(SFL::Core::Ports::SectionRegistry::ConflictError)
    expect(db[:sections].where(section_id: "README#intro").get(:id)).to eq(id)
    expect(db[:sections].where(section_id: "README#intro").get(:document_id)).to eq(db[:documents].where(document_key: "/a/README.md").get(:id))
  end

  it "rolls the section write back with the clauses when the transaction fails" do
    reg = registry("c")
    expect do
      reg.transaction do
        reg.register(unit("doc#a"), 0)
        raise Sequel::Rollback
      end
    end.not_to raise_error

    expect([db[:documents].count, db[:sections].count]).to eq([0, 0])
  end

  it "normalizes the collection name and works without a logger when a document moves" do
    store(registry(" old "), unit("doc#a"))

    expect(collection_of("/p/doc.md")).to eq("old")
    expect { store(described_class.new(db, collection: "new"), unit("doc#a")) }.not_to raise_error
    expect(collection_of("/p/doc.md")).to eq("new")
  end

  it "names the collection the document moved from when other collections exist" do
    store(registry("first"), unit("other#a", key: "/p/other.md"))
    store(registry("old"), unit("doc#a"))
    store(registry("new"), unit("doc#a"))

    expect(logger).to have_received(:warn)
      .with("document moved", document_key: "/p/doc.md", from_collection: "old", to_collection: "new")
  end

  it "rolls back only its own savepoint inside an enclosing transaction" do
    reg = registry("c")
    db.transaction do
      db[:collections].insert(name: "outer")
      reg.transaction do
        reg.register(unit("doc#a"), 0)
        raise Sequel::Rollback
      end
    end

    expect(db[:collections].select_map(:name)).to include("outer")
    expect(db[:documents].count).to eq(0)
  end

  describe "#written and #reconcile" do
    it "reports the section ids each run wrote, by document_key, once each" do
      reg = registry("c")
      store(reg, unit("doc#a"))
      store(reg, unit("doc#a"))
      store(reg, unit("other#x", key: "/p/other.md"))

      expect(reg.written).to eq("/p/doc.md" => ["doc#a"], "/p/other.md" => ["other#x"])
    end

    it "removes only the given document's sections that the run did not write" do
      store(registry("c"), unit("doc#a"))
      store(registry("c"), unit("doc#b"))
      store(registry("c"), unit("other#x", key: "/p/other.md"))

      reg = registry("c")
      store(reg, unit("doc#a"))
      expect(reg.reconcile("/p/doc.md" => ["doc#a"])).to eq(1)
      expect(db[:sections].select_map(:section_id)).to contain_exactly("doc#a", "other#x")
    end

    it "removes every section of a document given an empty list, and sets its section_count to 0" do
      store(registry("c"), unit("doc#a"), clauses: 2)

      expect(registry("c").reconcile("/p/doc.md" => [])).to eq(1)
      expect([db[:sections].count, db[:clauses].count, db[:documents].get(:section_count)]).to eq([0, 0, 0])
    end

    it "skips a document key that is not stored" do
      expect(registry("c").reconcile("/p/none.md" => ["none#a"])).to eq(0)
    end

    it "logs each removal with keyword fields and no section text" do
      store(registry("c"), unit("doc#a"))
      store(registry("c"), unit("doc#b"))

      registry("c").reconcile("/p/doc.md" => ["doc#b"])
      expect(logger).to have_received(:info).with("stale sections removed", document_key: "/p/doc.md", removed: 1)
    end
  end

  describe "a section id stored under another document" do
    before { store(registry("alpha"), unit("README#intro", key: "/a/README.md"), clauses: 2) }

    let(:intruder) { unit("README#intro", key: "/b/README.md") }

    it "raises ConflictError and rolls back the clause replacement and every section write" do
      expect { store(registry("beta"), intruder, clauses: 5) }
        .to raise_error(SFL::Core::Ports::SectionRegistry::ConflictError, %r{README#intro belongs to /a/README.md, not /b/README.md})

      owner = db[:sections].join(:documents, id: :document_id).where(section_id: "README#intro").get(:document_key)
      expect(owner).to eq("/a/README.md")
      expect(db[:clauses].where(section_id: "README#intro").count).to eq(2)
      expect(db[:documents].select_map(:document_key)).to eq(["/a/README.md"])
    end

    it "logs a warning with the section id and both document keys" do
      expect { store(registry("beta"), intruder) }.to raise_error(SFL::Core::Ports::SectionRegistry::ConflictError)
      expect(logger).to have_received(:warn).with("section owned by another document",
        section_id: "README#intro", document_key: "/b/README.md", owner_document_key: "/a/README.md")
    end
  end
end
