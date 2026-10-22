# frozen_string_literal: true

require "json"

module SFL
  module Export
    # Writes one JSON object per clause, one per line.
    module JsonlWriter
      extend self

      EXTENSION = "jsonl"

      # @param records [Array<ClauseRecord>]
      # @param io [#write]
      # @return [void]
      def call(records, io)
        records.each { |record| io.write(JSON.generate(record.to_json_hash), "\n") }
        nil
      end
    end
  end
end
