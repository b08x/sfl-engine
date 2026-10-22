# frozen_string_literal: true

module SFL
  module Export
    # Writes a heading per document, a nested heading per nested section
    # (deeper sections get deeper headings), a speaker line for each turn,
    # then the clause text.
    module MarkdownWriter
      extend self

      EXTENSION = "md"

      # Markdown has six heading levels; deeper sections reuse the last one.
      MAX_LEVEL = 6

      # @param records [Array<ClauseRecord>]
      # @param io [#write]
      # @return [void]
      def call(records, io)
        document = section = nil
        records.each do |record|
          pick = record.pick
          io.write(document_heading(pick)) unless pick.document_key == document
          io.write(section_heading(pick)) unless pick.section_id == section && pick.document_key == document
          document = pick.document_key
          section = pick.section_id
          io.write(record.text, "\n\n")
        end
        nil
      end

      private def document_heading(pick) = "# #{pick.title || pick.document_key}\n\n"

      private def section_heading(pick)
        return "**#{pick.speaker}:**\n\n" if pick.speaker
        return "" if pick.label.to_s.empty?

        "#{'#' * [pick.depth + 2, MAX_LEVEL].min} #{pick.label}\n\n"
      end
    end
  end
end
