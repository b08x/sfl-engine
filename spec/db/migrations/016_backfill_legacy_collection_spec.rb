# frozen_string_literal: true

require "spec_helper"

# Fact 18: the migration creates one document per distinct section id prefix
# before `#` and one section per distinct clause section id, all in a
# collection named `legacy`. Migrates the test database down to 015, seeds
# clauses, migrates back up, and leaves the schema at the latest version.
RSpec.describe "migration 016_backfill_legacy_collection" do # rubocop:disable RSpec/DescribeClass -- a migration, not a class
  let(:db) { SFL::Store::StoreTestDb.db }
  let(:dir) { "db/migrations" }

  def migrate(target = nil) = Sequel::Migrator.run(db, dir, **{ target: }.compact)

  def seed_clause(external_id, section_id)
    db[:clauses].insert(external_id:, text: "text", section_id:, sentence_index: 0, root_index: 0)
  end

  before do
    SFL::Store::StoreTestDb.clean!
    migrate(15)
  end

  after do
    migrate
    SFL::Store::StoreTestDb.clean!
  end

  it "creates the legacy collection with one document per prefix and one section per section id" do
    seed_clause("c1", "chat#turn-1")
    seed_clause("c2", "chat#turn-1")
    seed_clause("c3", "chat#turn-2")
    seed_clause("c4", "notes#intro")
    seed_clause("c5", "bare-id")
    migrate(16)

    legacy = db[:collections].where(name: "legacy").first
    documents = db[:documents].where(collection_id: legacy[:id]).order(:document_key)
    expect(documents.select_map(%i[document_key section_count])).to eq([["bare-id", 1], ["chat", 2], ["notes", 1]])

    sections = db[:sections].order(:section_id).select_map(%i[section_id kind clause_count ordinal])
    expect(sections).to eq([
      ["bare-id", "unknown", 1, 1],
      ["chat#turn-1", "turn", 2, 1],
      ["chat#turn-2", "turn", 1, 2],
      ["notes#intro", "unknown", 1, 1],
    ])
  end

  it "creates no legacy collection when there are no clauses" do
    migrate(16)

    expect(db[:collections].count).to eq(0)
  end

  it "removes the legacy collection, its documents and sections on rollback" do
    seed_clause("c1", "chat#turn-1")
    migrate(16)
    migrate(15)

    expect([db[:collections].count, db[:documents].count, db[:sections].count]).to eq([0, 0, 0])
    expect(db[:clauses].count).to eq(1)
  end
end
