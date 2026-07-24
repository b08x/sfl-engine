# frozen_string_literal: true

require "yajl"

module SFL
  module Core
    module Loaders
      # Generic ingestion for arbitrary JSON/JSONL corpora — one record,
      # one Unit. Like CsvSource, a JSON file carries no fixed schema of
      # its own, so field names are injected rather than assumed;
      # `text_key:` is the only required one. `.json` is parsed as one
      # array of records; `.jsonl`/`.ndjson` as one record per line.
      class JsonSource
        include Source

        JSONL_EXTENSIONS = %w[.jsonl .ndjson].freeze

        # @param path [String, Pathname]
        # @param text_key [Symbol] key holding unit text
        # @param file_id [String, nil]
        # @param document_id_key [Symbol, nil] key for a per-record id;
        #   defaults to "#{file_id}#row-{n}" when absent
        # @param speaker_key [Symbol, nil]
        # @param heading_key [Symbol, nil]
        # @param skip_empty [Boolean] drop records whose text is blank
        # rubocop:disable Metrics/ParameterLists -- one required key plus four optional
        # key-name mappings (a JSON record has no schema of its own to infer these from) and
        # skip_empty; matches CsvSource's identical shape for the tabular-vs-record analogue.
        def initialize(
          path,
          text_key:,
          file_id: nil,
          document_id_key: nil,
          speaker_key: nil,
          heading_key: nil,
          skip_empty: true
        )
          @path = path.to_s
          @text_key = text_key
          @file_id = file_id || File.basename(@path, ".*")
          @document_id_key = document_id_key
          @speaker_key = speaker_key
          @heading_key = heading_key
          @skip_empty = skip_empty
        end
        # rubocop:enable Metrics/ParameterLists

        def each_unit
          return to_enum(:each_unit) unless block_given?

          records.each_with_index do |record, index|
            text = record[@text_key].to_s.strip
            next if @skip_empty && text.empty?

            yield build_unit(record, text, index)
          end
        end

        private def records
          jsonl? ? jsonl_records : Yajl::Parser.parse(File.read(@path), symbolize_keys: true)
        end

        private def jsonl?
          JSONL_EXTENSIONS.include?(File.extname(@path).downcase)
        end

        private def jsonl_records
          File.readlines(@path).map(&:strip).reject(&:empty?).map do |line|
            Yajl::Parser.parse(line, symbolize_keys: true)
          end
        end

        private def build_unit(record, text, index)
          Types::Unit.new(
            document_id: document_id_for(record, index),
            text:,
            heading: @heading_key ? record[@heading_key] : nil,
            speaker: @speaker_key ? record[@speaker_key] : nil,
            metadata: { "file_id" => @file_id, "record" => record }
          )
        end

        private def document_id_for(record, index)
          explicit = @document_id_key && record[@document_id_key]
          explicit ? explicit.to_s : "#{@file_id}#row-#{index}"
        end
      end
    end
  end
end
