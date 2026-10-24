# frozen_string_literal: true

require "sequel"

module SFL
  module Store
    # Postgres SectionRegistry for one ingest into one collection.
    #
    # The first unit of each document this registry sees claims the document:
    # a document whose key exists in another collection moves here (with its
    # sections) and a warning names both collections. Each unit is an upsert
    # keyed on section_id: a stored section keeps its surrogate id and is
    # updated in place, and its clauses are replaced by ClauseStore#replace_section
    # before #register runs. Sections are written in ordinal order. A
    # section id stored under a different document raises
    # Core::Ports::SectionRegistry::ConflictError before any write here, and
    # the transaction rolls the caller's clause replacement back.
    #
    # #written reports the section ids this registry wrote, by document_key.
    # #reconcile removes the stored sections of a document that a run did not
    # write, once the run has written every file it means to write.
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
        @written = {}
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
        (@written[key] ||= []) << unit.section_id
        @documents.refresh_section_count(doc[:id])
        nil
      end

      # @return [Hash{String => Array<String>}] section ids this registry has written, by document_key
      def written = @written.transform_values(&:uniq)

      # Deletes, for each document given, the stored sections whose ids are not
      # in its list, with their clauses. Clauses go first, because they reference
      # a section by section_id. Each document is one transaction. A document
      # that is not stored is skipped.
      # @param written [Hash{String => Array<String>}] document_key => section ids the run wrote
      # @return [Integer] sections deleted
      def reconcile(written)
        written.sum { |key, ids| reconcile_document(key, ids) }
      end

      private def reconcile_document(key, ids)
        doc = @documents.find(key)
        return 0 if doc.nil?

        stale = @db[:sections].where(document_id: doc[:id]).exclude(section_id: ids.uniq).select(:section_id)
        removed = @db.transaction do
          @db[:clauses].where(section_id: stale).delete
          deleted = @db[:sections].where(section_id: stale).delete
          @documents.refresh_section_count(doc[:id])
          deleted
        end
        @logger.info("stale sections removed", document_key: key, removed:) if removed.positive?
        removed
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
