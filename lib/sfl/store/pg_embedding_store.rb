# frozen_string_literal: true

require "sequel"
require "pgvector"

module SFL
  module Store
    # Postgres-backed EmbeddingStore (pgvector). `#replace_document` deletes
    # and re-inserts in one transaction, same F7 idempotency-as-contract
    # rationale as PgClauseStore — a document re-embedded twice never
    # leaves stale vectors behind.
    #
    # Legacy's EmbeddingRepository#store inserted one row at a time (it was
    # only ever called once per clause) and relied on a
    # Sequel::UniqueConstraintViolation rescue-and-update fallback for the
    # rare re-embed. That fallback isn't needed here: #replace_document
    # controls delete-then-insert atomically, so the (clause_id, model)
    # unique index (db/migrations/004) can never be hit on the insert side.
    class PgEmbeddingStore
      include Core::Ports::EmbeddingStore

      DEFAULT_MODEL = ENV.fetch("EMBEDDING_MODEL", "embeddinggemma:latest")

      # @param db [Sequel::Database]
      # @param model [String] embedding model identifier stored alongside
      #   each vector, so multiple models' vectors for the same clause can
      #   coexist (see the [:clause_id, :model] unique index).
      def initialize(db, model: DEFAULT_MODEL)
        @db = db
        @model = model
      end

      # @param document_id [String] embeddings has no document_id column of
      #   its own, so the delete scope is every clause_id belonging to this
      #   document per the `clauses` table — NOT just
      #   embeddings_by_clause_id's keys. Scoping by the new payload's own
      #   keys instead would only clear rows being immediately
      #   re-inserted, leaving any clause dropped from this embed run (or
      #   whose clause was deleted) with a stale vector — the exact F7
      #   failure mode this method exists to close.
      # @param embeddings_by_clause_id [Hash<String, Array<Float>>]
      # @return [void]
      def replace_document(document_id, embeddings_by_clause_id)
        document_clause_ids = @db[:clauses].where(document_id:).select(:external_id)

        @db.transaction do
          @db[:embeddings].where(clause_id: document_clause_ids, model: @model).delete

          next if embeddings_by_clause_id.empty?

          @db[:embeddings].multi_insert(embeddings_by_clause_id.map { |clause_id, vector| row(clause_id, vector) })
        end
        nil
      end

      private def row(clause_id, vector)
        {
          clause_id:,
          embedding: Pgvector.encode(vector),
          model: @model,
          created_at: Time.now,
        }
      end
    end
  end
end
