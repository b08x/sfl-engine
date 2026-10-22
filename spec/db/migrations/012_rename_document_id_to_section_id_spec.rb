# frozen_string_literal: true

require "spec_helper"

RSpec::Matchers.define_negated_matcher :exclude, :include

# Fact 1: `clauses` and `review_queue` carry `section_id`, not `document_id`.
# Migrates the dedicated test database down to 011 and back, so it always
# leaves the schema at the latest version.
RSpec.describe "migration 012_rename_document_id_to_section_id" do # rubocop:disable RSpec/DescribeClass -- a migration, not a class
  let(:db) { SFL::Store::StoreTestDb.db }
  let(:dir) { "db/migrations" }

  def columns(table) = db.schema(table, reload: true).map(&:first)
  def indexes(table) = db.indexes(table).keys
  def migrate(target = nil) = Sequel::Migrator.run(db, dir, **{ target: }.compact)

  def seed_review_row
    db[:review_queue].insert(id: "rq-1", modality: "text", document_id: "file#turn-3",
      generated_text: "text", reason: "fallback_annotation")
  end

  before { SFL::Store::StoreTestDb.clean! }

  after do
    migrate
    SFL::Store::StoreTestDb.clean!
  end

  it "leaves section_id and no document_id on clauses and review_queue at the latest version" do
    expect(columns(:clauses)).to include(:section_id).and(exclude(:document_id))
    expect(columns(:review_queue)).to include(:section_id).and(exclude(:document_id))
  end

  it "renames the indexes with their columns" do
    expect(indexes(:clauses)).to include(:clauses_section_id_index)
    expect(indexes(:review_queue)).to include(:idx_review_queue_section_id)
  end

  it "keeps seeded values across migrate, rollback and migrate" do
    migrate(11)
    seed_review_row

    migrate
    expect(db[:review_queue].get(:section_id)).to eq("file#turn-3")

    migrate(11)
    expect(columns(:review_queue)).to include(:document_id).and(exclude(:section_id))
    expect(indexes(:clauses)).to include(:clauses_document_id_index)
    expect(db[:review_queue].get(:document_id)).to eq("file#turn-3")
  end
end
