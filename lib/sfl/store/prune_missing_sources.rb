# frozen_string_literal: true

require "sequel"

module SFL
  module Store
    # Deletes documents whose source file no longer exists on disk, together
    # with their sections and the clauses under those sections. Rules:
    #   - an archived document (archived_at not null) is kept, counted as kept_archived;
    #     its source is not looked up.
    #   - an empty or null source_path cannot be checked: kept, counted as kept_unreadable,
    #     logged as source_path_missing.
    #   - a lookup that raises Errno::ENOENT means missing: deleted.
    #   - a lookup that raises any other error means unreadable: kept, counted as
    #     kept_unreadable, logged as source_unreadable.
    # Only database rows change. No file is read, written, renamed or removed.
    class PruneMissingSources
      COMPONENT = "PruneMissingSources"

      # @param db [Sequel::Database]
      # @param logger [Core::Ports::Logger] receives keyword fields only
      def initialize(db, logger:)
        @db = db
        @logger = logger
      end

      # @param dry_run [Boolean] count what a real run would delete; change nothing
      # @return [Hash{Symbol => Integer}] {deleted:, kept_archived:, kept_unreadable:}
      def call(dry_run: false)
        counts = { deleted: 0, kept_archived: 0, kept_unreadable: 0 }
        @db[:documents].select(:id, :document_key, :source_path, :archived_at).order(:id).each do |doc|
          outcome = sweep(doc, dry_run)
          counts[outcome] += 1 if counts.key?(outcome)
        end
        counts
      end

      # @return [Symbol] :deleted, :kept_archived, :kept_unreadable or :present
      private def sweep(doc, dry_run)
        return :kept_archived if doc[:archived_at]

        verdict = source_verdict(doc)
        return verdict unless verdict == :missing
        return :deleted if dry_run

        delete_document(doc[:id]) ? :deleted : :kept_archived
      end

      # @return [Symbol] :missing, :present or :kept_unreadable
      private def source_verdict(doc)
        path = doc[:source_path]
        if path.nil? || path.strip.empty?
          @logger.warn(component: COMPONENT, document_key: sanitize(doc[:document_key]), reason: "source_path_missing")
          return :kept_unreadable
        end

        File.stat(path)
        :present
      rescue Errno::ENOENT
        :missing
      rescue
        @logger.warn(component: COMPONENT, document_key: sanitize(doc[:document_key]), reason: "source_unreadable")
        :kept_unreadable
      end

      # Deletes the clauses and sections explicitly, then the document, in one
      # transaction. The document delete is guarded by archived_at, so a document
      # archived after the listing is kept.
      # @return [Boolean] true when the document row was deleted
      private def delete_document(id)
        deleted = false
        @db.transaction do
          section_ids = @db[:sections].where(document_id: id).select_map(:section_id)
          @db[:clauses].where(section_id: section_ids).delete
          @db[:sections].where(document_id: id).delete
          deleted = @db[:documents].where(id:, archived_at: nil).delete.positive?
          raise Sequel::Rollback unless deleted
        end
        deleted
      end

      # One line, no control characters.
      private def sanitize(value) = value.to_s.gsub(/[[:cntrl:]]/, "?")
    end
  end
end
