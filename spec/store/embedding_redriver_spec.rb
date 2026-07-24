# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Store::EmbeddingRedriver do
  subject(:redriver) { described_class.new(db:, embedder:, embedding_store:) }

  let(:db) { SFL::Store::StoreTestDb.db }
  let(:embedding_store) { SFL::Store::PgEmbeddingStore.new(db, model:) }
  let(:model) { SFL::Store::PgEmbeddingStore::DEFAULT_MODEL }
  let(:good_vector) { Array.new(768, 0.5) }
  let(:embedder) do
    SFL::Core::Ports::Fake::Embedder.new(
      vectors: { "always fails" => [] },
      default: good_vector
    )
  end

  before { SFL::Store::StoreTestDb.clean! }

  def insert_clause(external_id:, document_id:, text:, embedding_status:)
    db[:clauses].insert(
      external_id:, text:, document_id:, sentence_index: 0, root_index: 0, embedding_status:
    )
  end

  def insert_embedding(clause_id:, vector: Array.new(768, 0.1))
    db[:embeddings].insert(clause_id:, embedding: Pgvector.encode(vector), model:, created_at: Time.now)
  end

  describe "#call" do
    it "picks up a never-embedded (pending) clause and moves it to embedded" do
      insert_clause(external_id: "c-pending", document_id: "doc-1", text: "pending text", embedding_status: "pending")

      redriver.call

      row = db[:clauses].where(external_id: "c-pending").first
      expect(row[:embedding_status]).to eq("embedded")
      expect(row[:embedding_error]).to be_nil
      expect(db[:embeddings].where(clause_id: "c-pending", model:).count).to eq(1)
    end

    it "retries a failed clause and moves it to embedded on success" do
      insert_clause(external_id: "c-failed", document_id: "doc-1", text: "failed text", embedding_status: "failed")
      db[:clauses].where(external_id: "c-failed").update(embedding_error: "previous failure")

      redriver.call

      row = db[:clauses].where(external_id: "c-failed").first
      expect(row[:embedding_status]).to eq("embedded")
      expect(row[:embedding_error]).to be_nil
    end

    it "leaves an already-embedded clause untouched — not re-embedded, not deleted" do
      insert_clause(external_id: "c-embedded", document_id: "doc-1", text: "already good", embedding_status: "embedded")
      insert_embedding(clause_id: "c-embedded", vector: Array.new(768, 0.9))
      insert_clause(external_id: "c-pending", document_id: "doc-1", text: "pending text", embedding_status: "pending")

      redriver.call

      row = db[:embeddings].where(clause_id: "c-embedded", model:).first
      expect(Pgvector.decode(row[:embedding])).to eq(Array.new(768, 0.9))
      expect(db[:clauses].where(external_id: "c-embedded").first[:embedding_status]).to eq("embedded")
    end

    it "keeps a clause failed (with an updated error) when the retry also fails, and reports it in the summary" do
      insert_clause(external_id: "c-stays-failed", document_id: "doc-2", text: "always fails",
        embedding_status: "failed")

      summary = redriver.call

      row = db[:clauses].where(external_id: "c-stays-failed").first
      expect(row[:embedding_status]).to eq("failed")
      expect(row[:embedding_error]).not_to be_nil
      expect(db[:embeddings].where(clause_id: "c-stays-failed").count).to eq(0)
      expect(summary[:still_failed]).to eq(1)
    end

    it "returns a summary counting documents processed, redriven, and still-failed clauses" do
      insert_clause(external_id: "c-1", document_id: "doc-1", text: "pending text", embedding_status: "pending")
      insert_clause(external_id: "c-2", document_id: "doc-2", text: "always fails", embedding_status: "failed")

      summary = redriver.call

      expect(summary).to eq(documents_processed: 2, redriven: 1, still_failed: 1)
    end

    it "does nothing when no clause needs (re-)embedding" do
      insert_clause(external_id: "c-1", document_id: "doc-1", text: "already good", embedding_status: "embedded")

      summary = redriver.call

      expect(summary).to eq(documents_processed: 0, redriven: 0, still_failed: 0)
    end
  end
end
