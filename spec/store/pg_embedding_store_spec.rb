# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Store::PgEmbeddingStore do
  subject(:store) { described_class.new(db, model: "test-model") }

  let(:db) { SFL::Store::StoreTestDb.db }

  before do
    SFL::Store::StoreTestDb.clean!
    db[:clauses].insert(
      external_id: "c-1", text: "hello", document_id: "doc-1",
      sentence_index: 0, root_index: 0
    )
    db[:clauses].insert(
      external_id: "c-2", text: "world", document_id: "doc-1",
      sentence_index: 1, root_index: 0
    )
  end

  # Not using `it_behaves_like "an embedding store port"` here (unlike
  # PgClauseStore) — that shared example writes a 2-dimensional vector
  # ([0.1, 0.2]), but this table's `embedding` column is a fixed
  # `vector(768)` (db/migrations/004): Postgres itself rejects a
  # dimension mismatch, which Fake::EmbeddingStore has no way to enforce
  # or reproduce. The behavior this adapter actually needs to satisfy is
  # covered by the examples below instead.
  describe "#replace_document" do
    it "bulk-inserts one embedding row per clause_id" do
      store.replace_document("doc-1", { "c-1" => Array.new(768, 0.1), "c-2" => Array.new(768, 0.2) })

      expect(db[:embeddings].where(model: "test-model").select_map(:clause_id)).to contain_exactly("c-1", "c-2")
    end

    it "does not leave stale vectors behind when the document is replaced again (F7)" do
      store.replace_document("doc-1", { "c-1" => Array.new(768, 0.1) })

      store.replace_document("doc-1", { "c-2" => Array.new(768, 0.2) })

      expect(db[:embeddings].where(model: "test-model").select_map(:clause_id)).to eq(["c-2"])
    end

    it "round-trips the encoded vector through pgvector" do
      vector = Array.new(768) { |i| i.zero? ? 1.0 : 0.0 }

      store.replace_document("doc-1", { "c-1" => vector })

      row = db[:embeddings].where(clause_id: "c-1", model: "test-model").first
      expect(Pgvector.decode(row[:embedding])).to eq(vector)
    end
  end
end
