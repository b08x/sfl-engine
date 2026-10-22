# frozen_string_literal: true

module SFL
  module Export
    # One exported clause together with its section's place in the corpus.
    ClauseRecord = Data.define(:pick, :id, :text, :ideational, :interpersonal) do
      # @return [Hash] the JSONL object for this clause
      def to_json_hash
        {
          collection: pick.collection,
          document_key: pick.document_key,
          source_path: pick.source_path,
          section_id: pick.section_id,
          section_path: pick.path.compact.join(" > "),
          speaker: pick.speaker,
          text:,
          ideational:,
          interpersonal:,
        }
      end
    end
  end
end
