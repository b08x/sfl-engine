# frozen_string_literal: true

require "sequel"

module SFL
  module Store
    # Postgres-backed documents, one row per whole item, keyed by
    # `document_key` (migration 014).
    class PgDocumentRepository
      # @param db [Sequel::Database]
      def initialize(db)
        @db = db
      end

      # Inserts the document, or updates it in place (including its
      # collection) when the key exists. Sets `updated_at` either way.
      # @param collection_id [Integer]
      # @param document_key [String]
      # @param source_path [String, nil]
      # @param title [String, nil]
      # @param source_type [String, nil]
      # @return [Hash] the stored row
      def upsert(collection_id:, document_key:, source_path: nil, title: nil, source_type: nil)
        now = Time.now
        row = { collection_id:, document_key:, source_path:, title:, source_type:, updated_at: now }
        @db[:documents]
          .insert_conflict(target: :document_key, update: row.except(:document_key))
          .insert(row.merge(ingested_at: now))
        find(document_key)
      end

      # @param document_key [String]
      # @return [Hash, nil]
      def find(document_key) = @db[:documents].where(document_key:).first

      # Moves a document, and with it all its sections, to another collection.
      # @param document_key [String]
      # @param collection_id [Integer]
      # @return [Integer] rows updated
      def move_to(document_key, collection_id)
        @db[:documents].where(document_key:).update(collection_id:, updated_at: Time.now)
      end

      # @param collection_id [Integer]
      # @return [Array<Hash>] by document_key
      def list_by_collection(collection_id) = @db[:documents].where(collection_id:).order(:document_key).all

      # Recounts a document's sections into `section_count`.
      # @param id [Integer] documents.id
      # @return [void]
      def refresh_section_count(id)
        count = @db[:sections].where(Sequel[:sections][:document_id] => id).count
        @db[:documents].where(id:).update(section_count: count)
        nil
      end
    end
  end
end
