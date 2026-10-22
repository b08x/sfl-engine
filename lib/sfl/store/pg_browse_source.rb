# frozen_string_literal: true

require "sequel"

module SFL
  module Store
    # Postgres BrowseSource. Reads the M1 data model through the existing
    # repositories (collections, documents, nested sections), clauses
    # through PgClauseStore, and the two review flows through
    # PgReviewQueueRepository and PgAnnotationReviewRepository.
    class PgBrowseSource
      include Core::Ports::BrowseSource

      # Upper bound on rows read from either review queue in one call.
      REVIEW_LIMIT = 10_000

      ANNOTATION_STATUS = { "accepted" => "accepted", "rejected" => "rejected" }.freeze

      # @param db [Sequel::Database]
      def initialize(db)
        @db = db
        @collections = PgCollectionRepository.new(db)
        @documents = PgDocumentRepository.new(db)
        @sections = PgSectionRepository.new(db)
        @clauses = PgClauseStore.new(db)
        @content = PgReviewQueueRepository.new(db)
        @annotation = PgAnnotationReviewRepository.new(db)
      end

      def collections = @collections.list.map { |row| row.slice(:id, :name) }

      def documents(collection_id)
        @documents.list_by_collection(collection_id).map { |row| row.slice(:id, :document_key, :title, :source_path) }
      end

      def sections(document_id) = @sections.tree(document_id).map { |row| section(row) }

      def clauses(section_id)
        @clauses.find_by_section(section_id).map do |clause|
          {
            id: clause.id,
            text: clause.text,
            section_id: clause.section_id,
            ideational: clause.ideational.to_h,
            interpersonal: clause.interpersonal.to_h,
          }
        end
      end

      # Pending items come from the repository; decided items are read from
      # the same table so the status filter can show them.
      def content_reviews
        pending = @content.pending(limit: REVIEW_LIMIT).fetch(:items)
        decided = @db[:review_queue].exclude(status: "pending").order(:created_at).all
        (pending + decided).map { |row| row.slice(:id, :section_id, :modality, :source_file, :generated_text, :reason, :status) }
      end

      def annotation_reviews
        statuses = latest_decisions
        @annotation.review_queue(limit: REVIEW_LIMIT).fetch(:clauses).each do |row|
          statuses[row[:id]] ||= { status: "pending" }
          statuses[row[:id]][:confidence] = confidence(row[:reasoning_trace])
        end
        statuses
      end

      def locate(section_ids)
        @db[:sections]
          .join(:documents, id: :document_id)
          .join(:collections, id: Sequel[:documents][:collection_id])
          .where(Sequel[:sections][:section_id] => section_ids)
          .select(
            Sequel[:sections][:section_id], Sequel[:sections][:label], Sequel[:documents][:document_key],
            Sequel[:documents][:source_path], Sequel[:collections][:name].as(:collection)
          )
          .all
          .to_h { |row| [row[:section_id], row.except(:section_id)] }
      end

      private def section(row)
        row.slice(:section_id, :label, :kind, :level, :ordinal, :clause_count)
          .merge(children: row[:children].map { |child| section(child) })
      end

      private def latest_decisions
        @db[:annotation_reviews].order(:reviewed_at).all.each_with_object({}) do |row, statuses|
          status = ANNOTATION_STATUS[row[:decision]]
          statuses[row[:clause_id]] = { status:, confidence: nil } if status
        end
      end

      # The trace arrives as a Sequel JSONB hash, which delegates to Hash.
      private def confidence(trace)
        trace.respond_to?(:to_h) ? trace.to_h["confidence"]&.to_f : nil
      end
    end
  end
end
