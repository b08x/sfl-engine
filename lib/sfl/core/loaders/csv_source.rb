# frozen_string_literal: true

require "csv"

module SFL
  module Core
    module Loaders
      # Generic ingestion for arbitrary tabular corpora — one row, one
      # Unit. Unlike the export/subtitle Sources, a CSV file carries no
      # fixed schema of its own, so column names are injected rather than
      # assumed; `text_column:` is the only required one.
      class CsvSource
        include Source

        # @param path [String, Pathname]
        # @param text_column [String] header of the column holding unit text
        # @param file_id [String, nil]
        # @param document_id_column [String, nil] header for a per-row id;
        #   defaults to "#{file_id}#row-{n}" when absent
        # @param speaker_column [String, nil]
        # @param heading_column [String, nil]
        # @param skip_empty [Boolean] drop rows whose text is blank
        # rubocop:disable Metrics/ParameterLists -- one required column plus four optional
        # column-name mappings (a CSV file has no schema of its own to infer these from) and
        # skip_empty; matches CsvSource's Unit-mapping job one-for-one, nothing here is padding.
        def initialize(
          path,
          text_column:,
          file_id: nil,
          document_id_column: nil,
          speaker_column: nil,
          heading_column: nil,
          skip_empty: true
        )
          @path = path.to_s
          @text_column = text_column
          @file_id = file_id || File.basename(@path, ".*")
          @document_id_column = document_id_column
          @speaker_column = speaker_column
          @heading_column = heading_column
          @skip_empty = skip_empty
        end
        # rubocop:enable Metrics/ParameterLists

        def each_unit
          return to_enum(:each_unit) unless block_given?

          ::CSV.foreach(@path, headers: true, encoding: "bom|utf-8").with_index do |row, index|
            text = row[@text_column].to_s.strip
            next if @skip_empty && text.empty?

            yield build_unit(row, text, index)
          end
        end

        private def build_unit(row, text, index)
          Types::Unit.new(
            document_id: document_id_for(row, index),
            text:,
            heading: @heading_column ? row[@heading_column] : nil,
            speaker: @speaker_column ? row[@speaker_column] : nil,
            metadata: { "file_id" => @file_id, "row" => row.to_h }
          )
        end

        private def document_id_for(row, index)
          explicit = @document_id_column && row[@document_id_column]
          explicit || "#{@file_id}#row-#{index}"
        end
      end
    end
  end
end
