# frozen_string_literal: true

require "kreuzberg"

module SFL
  module Core
    module Loaders
      # Ported from legacy PdfLoader (logic unchanged; emits Types::Unit
      # instead of a loader-local Section struct).
      #
      # PDFs have no heading structure to chunk by, and extracted page
      # text loses blank-line paragraph breaks entirely — every wrapped
      # line and every true paragraph boundary both collapse to the same
      # "\r\n", so a blank-line split heuristic (the natural
      # MarkdownSource analogue) silently produces one giant chunk per
      # page on real PDFs. Kreuzberg's own Config::Chunking is
      # sentence-boundary-aware and anchors each chunk to
      # first_page/last_page, so units are derived from that instead of a
      # paragraph-detection heuristic that doesn't survive extraction.
      class PdfSource
        include Source

        # ~paragraph-sized; no overlap so clauses aren't extracted twice
        # across adjacent chunks (overlap exists for embedding/retrieval
        # use cases, not clause-extraction).
        DEFAULT_CHUNKING = Kreuzberg::Config::Chunking.new(max_chars: 1000, max_overlap: 0).freeze

        # @param path [String, Pathname]
        # @param file_id [String, nil] Override the auto-derived file identifier.
        # @param skip_empty [Boolean] Drop chunks whose cleaned text is blank.
        # @param min_length [Integer] Minimum character length of cleaned text to emit.
        def initialize(path, file_id: nil, skip_empty: true, min_length: 40)
          @path = path.to_s
          @file_id = file_id || File.basename(@path, ".*")
          @skip_empty = skip_empty
          @min_length = min_length
        end

        def each_unit
          return to_enum(:each_unit) unless block_given?

          config = Kreuzberg::Config::Extraction.new(chunking: DEFAULT_CHUNKING)
          result = Kreuzberg.extract_file_sync(path: @path, config:)
          fm = pdf_frontmatter(result)

          chunks(result).each_with_index do |chunk, index|
            cleaned = chunk.content.strip
            next if @skip_empty && cleaned.length < @min_length

            yield build_unit(cleaned, chunk:, index:, frontmatter: fm)
          end
        end

        private def chunks(result)
          return result.chunks unless result.chunks.nil? || result.chunks.empty?

          [Kreuzberg::Result::Chunk.new(result.content, nil, nil, nil, 0, 1, nil, nil, nil, nil)]
        end

        # above it are the only real logic, already as short as the format string allows.
        private def build_unit(text, chunk:, index:, frontmatter:)
          label = chunk.first_page ? "p#{chunk.first_page}" : "chunk#{index + 1}"
          slug = "#{label}-#{index + 1}"

          Types::Unit.new(
            document_id: "#{@file_id}##{slug}",
            text:,
            heading: "#{label} §#{index + 1}",
            metadata: {
              "file_id" => @file_id,
              "heading_level" => 1,
              "heading_slug" => slug,
              "frontmatter" => frontmatter,
            }
          )
        end
        # Builds a frontmatter hash from Kreuzberg's document-level metadata.
        # Returns nil when the PDF carries no extractable metadata — avoids
        # polluting downstream classifiers with empty hashes.
        # rubocop:disable Metrics/CyclomaticComplexity, -- one Hash
        # literal plus a #select filtering out absent fields; the branching is inherent to
        # "only include fields Kreuzberg actually extracted," not decomposable further.
        private def pdf_frontmatter(result)
          meta = result.metadata
          return nil unless meta.is_a?(Hash)

          fields = {
            "title" => non_blank(meta["title"]),
            "author" => non_blank(meta["author"]),
            "tags" => result.extracted_keywords&.filter_map(&:text) || [],
            "last updated" => parse_pdf_date(meta["created"] || meta["creation_date"]),
          }.select { |_key, value| value && value != [] }

          fields.empty? ? nil : fields
        end
        # rubocop:enable Metrics/CyclomaticComplexity

        private def non_blank(val)
          str = val.to_s.strip
          str.empty? ? nil : str
        end

        private def parse_pdf_date(date_str)
          require "time"
          Time.parse(date_str.to_s)
        rescue ArgumentError, TypeError
          nil
        end
      end
    end
  end
end
