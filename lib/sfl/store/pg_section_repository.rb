# frozen_string_literal: true

require "sequel"

module SFL
  module Store
    # Postgres-backed sections (migration 015). A section belongs to one
    # document through the `sections.document_id` foreign key and may nest
    # under another section through `parent_section_id`.
    class PgSectionRepository
      COLUMNS = %i[parent_section_id ordinal kind label level clause_count].freeze

      # @param db [Sequel::Database]
      def initialize(db)
        @db = db
      end

      # Inserts or updates one section. A parent that is not stored is
      # dropped, so the row lands at the top level instead of failing. A
      # section stored under another document is not moved.
      # @param doc_id [Integer] documents.id
      # @param section_id [String]
      # @param fields [Hash] any of COLUMNS
      # @return [void]
      # @raise [Core::Ports::SectionRegistry::ConflictError] when another document owns section_id
      def upsert(doc_id, section_id, **fields)
        fields = fields.slice(*COLUMNS)
        fields[:parent_section_id] = nil unless exists?(fields[:parent_section_id])
        row = fields.merge(document_id: doc_id, updated_at: Time.now)
        written = @db[:sections]
          .insert_conflict(target: :section_id, update: row, update_where: { Sequel[:sections][:document_id] => doc_id })
          .returning(:section_id).insert(row.merge(section_id:))
        return if written.any?

        raise Core::Ports::SectionRegistry::ConflictError, "section #{section_id} belongs to another document"
      end

      # @param section_id [String]
      # @return [String, nil] document_key of the document that owns section_id
      def owner_key(section_id)
        @db[:sections].join(:documents, id: :document_id)
          .where(Sequel[:sections][:section_id] => section_id).get(Sequel[:documents][:document_key])
      end

      # Deletes a document's sections, and the clauses stored under them,
      # except the ids in +keep+.
      # @param doc_id [Integer]
      # @param keep [Array<String>]
      # @return [Integer] sections deleted
      def replace_for_document(doc_id, keep: [])
        stale = owned_by(doc_id).exclude(section_id: keep).select(:section_id)
        @db[:clauses].where(section_id: stale).delete
        @db[:sections].where(section_id: stale).delete
      end

      # @param doc_id [Integer]
      # @return [Array<Hash>] the document's top-level sections in ordinal
      #   order, each with `children:` nested the same way
      def tree(doc_id)
        rows = owned_by(doc_id).order(:ordinal).all
        by_parent = rows.group_by { |row| row[:parent_section_id] }
        build = -> (parent) { by_parent.fetch(parent, []).map { |row| row.merge(children: build.call(row[:section_id])) } }
        build.call(nil)
      end

      # @param section_id [String]
      # @return [Array<Hash>] direct children in ordinal order
      def children(section_id) = @db[:sections].where(parent_section_id: section_id).order(:ordinal).all

      private def owned_by(doc_id) = @db[:sections].where(document_id: doc_id)

      private def exists?(section_id) = section_id && !@db[:sections].where(section_id:).empty?
    end
  end
end
