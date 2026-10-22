# frozen_string_literal: true

require "sequel"

module SFL
  module Store
    # Deletes a collection with its documents, sections and the clauses stored
    # under those sections, in one transaction. Clause payloads and embeddings
    # go with their clauses (ON DELETE CASCADE).
    class CollectionPurger
      # @param db [Sequel::Database]
      def initialize(db)
        @db = db
      end

      # @param name [String] matched ignoring case
      # @return [Hash] {collections:, documents:, sections:, clauses:} rows deleted
      # @raise [Store::Error] when no collection has this name
      def purge(name)
        collection = PgCollectionRepository.new(@db).find(name)
        raise Error, "no collection named #{name.inspect}" unless collection

        @db.transaction { delete_all(collection[:id]) }
      end

      private def delete_all(collection_id)
        documents = @db[:documents].where(collection_id:)
        sections = @db[:sections].where(Sequel[:sections][:document_id] => documents.select(:id))
        counts = { documents: documents.count, sections: sections.count }
        counts[:clauses] = @db[:clauses].where(section_id: sections.select(:section_id)).delete
        counts[:collections] = @db[:collections].where(id: collection_id).delete
        counts.slice(:collections, :documents, :sections, :clauses)
      end
    end
  end
end
