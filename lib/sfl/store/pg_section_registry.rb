# frozen_string_literal: true

require "sequel"

module SFL
  module Store
    # Postgres SectionRegistry for one ingest into one collection.
    #
    # The first unit of each document this registry sees claims the document:
    # a document whose key exists in another collection moves here (with all
    # its sections) and a warning names both collections; the document's
    # earlier sections and their clauses are deleted, except the section being
    # registered, whose clauses ClauseStore#replace_section has just written.
    # Later units of the same document add sections in ordinal order. A
    # section id stored under a different document raises
    # Core::Ports::SectionRegistry::ConflictError before any write here, and
    # the transaction rolls the caller's clause replacement back.
    class PgSectionRegistry
      include Core::Ports::SectionRegistry

      # @param db [Sequel::Database]
      # @param collection [String] found or created on first use
      # @param logger [Core::Ports::Logger]
      def initialize(db, collection:, logger: Core::Ports::Null::Logger.new)
        @db = db
        @collection_name = Core::CollectionName.normalize(collection)
        @logger = logger
        @collections = PgCollectionRepository.new(db)
        @documents = PgDocumentRepository.new(db)
        @sections = PgSectionRepository.new(db)
        @claimed = {}
      end

      # Joins an enclosing transaction (PgClauseStore#replace_section's own
      # transaction nests inside this one).
      def transaction(&) = @db.transaction(savepoint: true, &)

      def register(unit, clause_count)
        key = Core::SectionShape.document_key(unit)
        refuse_move(unit.section_id, key)
        claim(unit, key) unless @claimed.key?(key)
        doc = @claimed[key]
        doc[:ordinal] += 1
        @sections.upsert(doc[:id], unit.section_id, **Core::SectionShape.attributes(unit),
          parent_section_id: unit.parent_section_id, ordinal: doc[:ordinal], clause_count:)
        @documents.refresh_section_count(doc[:id])
        nil
      end

      private def collection = @collection ||= @collections.find_or_create(@collection_name)

      private def refuse_move(section_id, key)
        owner = @sections.owner_key(section_id)
        return if owner.nil? || owner == key

        @logger.warn("section owned by another document", section_id:, document_key: key, owner_document_key: owner)
        raise Core::Ports::SectionRegistry::ConflictError, "section #{section_id} belongs to #{owner}, not #{key}"
      end

      private def claim(unit, key)
        warn_if_moving(key)
        row = @documents.upsert(collection_id: collection[:id], **Core::SectionShape.document(unit))
        @sections.replace_for_document(row[:id], keep: [unit.section_id])
        @claimed[key] = { id: row[:id], ordinal: 0 }
      end

      private def warn_if_moving(key)
        existing = @documents.find(key)
        return unless existing && existing[:collection_id] != collection[:id]

        from = @db[:collections].where(id: existing[:collection_id]).get(:name)
        @logger.warn("document moved", document_key: key, from_collection: from, to_collection: collection[:name])
      end
    end
  end
end
