# frozen_string_literal: true

require "sequel"

module SFL
  module Store
    # Archive state of one document, selected by exact document_key. Archive
    # sets documents.archived_at to the current time; unarchive sets it to
    # null. Neither writes updated_at. A key that matches no row raises, so a
    # wildcard or empty key changes nothing.
    class DocumentArchive
      # @param db [Sequel::Database]
      def initialize(db)
        @db = db
      end

      # @param document_key [String] exact key, never a pattern
      # @return [Symbol] :archived, or :already_archived (archived_at is left as it was)
      # @raise [Store::Error] when no document has this key
      def archive(document_key)
        return :archived if documents.where(document_key:, archived_at: nil).update(archived_at: Time.now) == 1

        ensure_exists!(document_key)
        :already_archived
      end

      # @param document_key [String] exact key, never a pattern
      # @return [Symbol] :unarchived, or :not_archived (nothing written)
      # @raise [Store::Error] when no document has this key
      def unarchive(document_key)
        return :unarchived if documents.where(document_key:).exclude(archived_at: nil).update(archived_at: nil) == 1

        ensure_exists!(document_key)
        :not_archived
      end

      private def documents = @db[:documents]

      private def ensure_exists!(document_key)
        raise Error, "no document matched #{document_key.inspect}" if documents.where(document_key:).empty?
      end
    end
  end
end
