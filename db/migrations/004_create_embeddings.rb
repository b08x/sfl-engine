# frozen_string_literal: true

# Clause embedding vectors (pgvector). Real FK to clauses.external_id (D5),
# cascade-deleted with the clause. `model` distinguishes vectors produced by
# different embedding models for the same clause (EMBEDDING_MODEL in .env
# defaults to "embeddinggemma:latest", a 768-dim Ollama model).
#
# Index type: HNSW, not legacy's IVFFlat. The installed `vector` extension
# (0.6.2) supports both. IVFFlat needs a representative sample of rows
# already in the table before it builds useful clusters (a fresh/small
# table gets a near-useless single-list index), and needs periodic
# REINDEXing as the table grows. HNSW builds incrementally with no
# training step and is pgvector's own recommended default for new indexes
# since 0.5.0 — worth the extra build/maintenance cost here since this
# table starts empty on every fresh environment. m/ef_construction are left
# at pgvector's defaults (16 / 64); revisit if a later slice's corpus size
# shows a measured need to tune them.
Sequel.migration do
  change do
    create_table(:embeddings) do
      primary_key :id
      foreign_key :clause_id, :clauses, type: String, null: false,
        key: :external_id, on_delete: :cascade
      column :embedding, "vector(768)"
      String :model, null: false, default: "embeddinggemma:latest"
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index %i[clause_id model], unique: true
      index :embedding, type: :hnsw, opclass: :vector_cosine_ops
    end
  end
end
