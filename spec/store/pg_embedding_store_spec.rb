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

    it "marks a clause with a real vector as embedded (F11)" do
      store.replace_document("doc-1", { "c-1" => Array.new(768, 0.1) })

      row = db[:clauses].where(external_id: "c-1").first
      expect(row[:embedding_status]).to eq("embedded")
      expect(row[:embedding_error]).to be_nil
    end

    it "does not insert an embeddings row for a nil/empty vector, and marks that clause failed instead " \
      "without aborting the rest of the document's write (F11)" do
      store.replace_document("doc-1", { "c-1" => Array.new(768, 0.1), "c-2" => [] })

      expect(db[:embeddings].where(clause_id: "c-2").count).to eq(0)
      failed_row = db[:clauses].where(external_id: "c-2").first
      expect(failed_row[:embedding_status]).to eq("failed")
      expect(failed_row[:embedding_error]).not_to be_nil

      succeeded_row = db[:clauses].where(external_id: "c-1").first
      expect(succeeded_row[:embedding_status]).to eq("embedded")
      expect(db[:embeddings].where(clause_id: "c-1", model: "test-model").count).to eq(1)
    end

    it "treats a nil vector the same as an empty vector (marks the clause failed, no row inserted)" do
      store.replace_document("doc-1", { "c-1" => nil })

      expect(db[:embeddings].where(clause_id: "c-1").count).to eq(0)
      expect(db[:clauses].where(external_id: "c-1").first[:embedding_status]).to eq("failed")
    end

    it "raises a clear SFL::Store::Error naming the configured model instead of a bare pgvector " \
      "PG::DataException when the embedder's output width doesn't match the migrated vector(768) column " \
      "(live-verified gap, 2026-08-02 — SFL_TASK_EMBEDDING_MODEL=mistral-embed returns 1024-dim vectors)" do
      expect do
        store.replace_document("doc-1", { "c-1" => Array.new(1024, 0.1) })
      end.to raise_error(SFL::Store::Error, /test-model.*1024-dimension.*768 dimensions/m)

      expect(db[:embeddings].where(clause_id: "c-1").count).to eq(0)
    end
  end
end
