# frozen_string_literal: true

require "spec_helper"

# Fact 19: purging deletes the collection, its documents, sections and clauses
# and reports the counts.
RSpec.describe SFL::Store::CollectionPurger do
  subject(:purger) { described_class.new(db) }

  let(:db) { SFL::Store::StoreTestDb.db }

  before { SFL::Store::StoreTestDb.clean! }

  def seed(collection, key, section_ids)
    collection_id = SFL::Store::PgCollectionRepository.new(db).find_or_create(collection)[:id]
    doc = SFL::Store::PgDocumentRepository.new(db).upsert(collection_id:, document_key: key)
    section_ids.each_with_index do |id, i|
      SFL::Store::PgSectionRepository.new(db).upsert(doc[:id], id, ordinal: i + 1, kind: "unknown")
      db[:clauses].insert(external_id: "#{id}-c", text: "t", section_id: id, sentence_index: 0, root_index: 0)
    end
  end

  it "deletes the collection with its documents, sections and clauses and returns the counts" do
    seed("legacy", "a", %w[a#1 a#2])
    seed("legacy", "b", %w[b#1])
    seed("keep", "k", %w[k#1])

    expect(purger.purge("LEGACY")).to eq(collections: 1, documents: 2, sections: 3, clauses: 3)
    expect(db[:collections].select_map(:name)).to eq(["keep"])
    expect([db[:documents].count, db[:sections].count, db[:clauses].count]).to eq([1, 1, 1])
  end

  it "raises Store::Error for an unknown collection" do
    expect { purger.purge("nope") }.to raise_error(SFL::Store::Error, /no collection named "nope"/)
  end
end
