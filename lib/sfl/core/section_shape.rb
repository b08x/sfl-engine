# frozen_string_literal: true

module SFL
  module Core
    # Derives the document and section fields a SectionRegistry stores from a
    # loader Unit. Shared by the Postgres and in-memory registries so both
    # apply the same rules.
    module SectionShape
      # @param unit [Types::Unit]
      # @return [String] the unit's document_key, or the section id prefix before `#`
      module_function def document_key(unit) = unit.document_key || unit.section_id.split("#", 2).first

      # @param unit [Types::Unit]
      # @return [Hash] {kind:, label:, level:} — a turn's label is its speaker
      module_function def attributes(unit)
        level = unit.metadata["heading_level"]
        if unit.speaker
          { kind: "turn", label: unit.speaker, level: nil }
        elsif level
          { kind: "heading", label: unit.heading, level: }
        else
          { kind: "block", label: unit.heading, level: nil }
        end
      end

      # @param unit [Types::Unit]
      # @return [Hash] {document_key:, source_path:, title:, source_type:}
      module_function def document(unit)
        key = document_key(unit)
        source_path = unit.source_path || key
        {
          document_key: key,
          source_path:,
          title: unit.metadata["conversation_title"] || File.basename(source_path),
          source_type: unit.metadata["source_type"],
        }
      end
    end
  end
end
