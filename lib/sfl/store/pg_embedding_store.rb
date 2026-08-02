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
    #
    # F11 contract (behavior change from this class's original version,
    # which assumed every vector in embeddings_by_clause_id was already
    # good): a nil/empty vector for a clause_id is a signal that this
    # clause's embed attempt failed for that one item, not a value to
    # insert. Those clause_ids get `clauses.embedding_status` flipped to
    # "failed" (with an error note) instead of an `embeddings` row: an
    # empty/garbage vector row would be worse than no row at all, since it
    # would look like a real (if degenerate) embedding to any downstream
    # cosine-similarity search. Every clause_id with a real vector gets
    # both its `embeddings` row AND `clauses.embedding_status` flipped to
    # "embedded" — the column doesn't just default correctly on insert
    # (see db/migrations/008), it also has to move off "pending"/"failed"
    # explicitly once a real vector lands, since a clause can carry a
    # stale "failed" status from an earlier attempt.
    class PgEmbeddingStore
      include Core::Ports::EmbeddingStore

      DEFAULT_MODEL = ENV.fetch("EMBEDDING_MODEL", "embeddinggemma:latest")

      # Must match db/migrations/004_create_embeddings.rb's `vector(768)`
      # column exactly. Root cause of a real failure (2026-08-02): pgvector
      # column width is fixed at migration time, but SFL_TASK_EMBEDDING_*
      # lets an operator pick any provider/model — e.g. mistral-embed
      # (1024-dim) instead of the default embeddinggemma:latest (768-dim).
      # Nothing coupled the two, so a mismatched pick reached Postgres raw
      # and surfaced deep inside Sequel#multi_insert as a bare
      # "PG::DataException: expected 768 dimensions, not 1024" with no
      # indication it was a config problem. #insert_succeeded now checks
      # this before the INSERT so the error names the actual cause.
      VECTOR_DIMENSIONS = 768

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
      # @param embeddings_by_clause_id [Hash<String, Array<Float>>] a nil or
      #   empty Array value for a clause_id means that clause's embed
      #   attempt failed — see the class comment's F11 contract. One failed
      #   item does not abort the rest of the document's write.
      # @return [void]
      def replace_document(document_id, embeddings_by_clause_id)
        document_clause_ids = @db[:clauses].where(document_id:).select(:external_id)
        succeeded, failed = embeddings_by_clause_id.partition { |_clause_id, vector| vector && !vector.empty? }

        @db.transaction do
          @db[:embeddings].where(clause_id: document_clause_ids, model: @model).delete

          insert_succeeded(succeeded)
          mark_embedded(succeeded)
          mark_failed(failed)
        end
        nil
      end

      # `succeeded` is an Array of [clause_id, vector] pairs from
      # Array#partition, not a Hash — Style/HashEachMethods' each_value
      # suggestion doesn't apply here (see mark_failed above).
      # rubocop:disable Style/HashEachMethods -- see comment above
      private def insert_succeeded(succeeded)
        return if succeeded.empty?

        succeeded.each { |_clause_id, vector| check_dimensions!(vector) }
        @db[:embeddings].multi_insert(succeeded.map { |clause_id, vector| row(clause_id, vector) })
      end
      # rubocop:enable Style/HashEachMethods

      private def check_dimensions!(vector)
        return if vector.size == VECTOR_DIMENSIONS

        raise Error, "embedding model #{@model.inspect} returned a #{vector.size}-dimension vector, but the " \
          "embeddings table is provisioned for #{VECTOR_DIMENSIONS} dimensions " \
          "(db/migrations/004_create_embeddings.rb). Check SFL_TASK_EMBEDDING_PROVIDER/SFL_TASK_EMBEDDING_MODEL " \
          "— the configured embedding model's output width must match the migrated column width."
      end

      private def mark_embedded(succeeded)
        return if succeeded.empty?

        clause_ids = succeeded.map(&:first)
        @db[:clauses].where(external_id: clause_ids).update(embedding_status: "embedded", embedding_error: nil)
      end

      # `failed` is an Array of [clause_id, vector] pairs from Array#partition,
      # not a Hash — Style/HashEachMethods' each_key/each_value suggestion
      # doesn't apply here.
      # rubocop:disable Style/HashEachMethods -- see comment above
      private def mark_failed(failed)
        failed.each do |clause_id, _vector|
          @db[:clauses].where(external_id: clause_id).update(
            embedding_status: "failed", embedding_error: "embedder returned no vector for this clause"
          )
        end
      end
      # rubocop:enable Style/HashEachMethods

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
