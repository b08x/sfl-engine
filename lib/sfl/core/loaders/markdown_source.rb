# frozen_string_literal: true

require "inkmark"
require "pragmatic_tokenizer"

module SFL
  module Core
    module Loaders
      # Ported from legacy MarkdownLoader (logic unchanged; emits
      # Types::Unit instead of a loader-local Section struct — see
      # Source's docstring for why). Bridges Inkmark's markdown parsing
      # into SFL::Core::Pipeline#compile by:
      #   1. Chunking a markdown document into heading-scoped sections via
      #      Inkmark.chunks_by_heading
      #   2. Rendering each section to HTML (Inkmark handles all structural
      #      markdown at the AST level), then stripping HTML tags to get
      #      clean prose — no `**bold**` or `[link](url)` reaching spaCy
      #   3. Dropping fenced code blocks (non-prose; corrupt POS/dep parses)
      #   4. Normalising via PragmaticTokenizer — URL removal, hashtag/mention
      #      stripping, token-level cleanup
      #   5. Emitting Units with document_id encoded as
      #      "#{file_id}##{section_slug}" for section-granular retrieval
      class MarkdownSource
        include Source

        # PragmaticTokenizer options for prose normalisation.
        # :all keeps numbers and punctuation so spaCy sees natural sentence
        # boundaries; remove_urls + clean strip noise that regex used to handle.
        TOKENIZER_OPTIONS = {
          language: "en",
          remove_urls: true,
          hashtags: :remove,
          mentions: :remove,
          clean: true,
          punctuation: :all,
          numbers: :all,
          downcase: false,
        }.freeze

        # HTML entities decoded before plain-text extraction.
        HTML_ENTITIES = {
          "&amp;" => "&",
          "&lt;" => "<",
          "&gt;" => ">",
          "&quot;" => '"',
          "&#39;" => "'",
          "&nbsp;" => " ",
        }.freeze

        # Punctuation tokens that attach to the preceding word (no leading space).
        CLOSING_PUNCT = %w[. , ! ? ; : ) \] } … -- -].to_set.freeze

        # @param path [String, Pathname]
        # @param file_id [String, nil] Override the auto-derived file identifier.
        # @param skip_empty [Boolean] Drop sections whose cleaned text is blank.
        # @param min_length [Integer] Minimum character length of cleaned text to emit.
        def initialize(path, file_id: nil, skip_empty: true, min_length: 40)
          @path = path.to_s
          @source = File.read(@path, encoding: "utf-8")
          @file_id = file_id || File.basename(@path, ".*")
          @skip_empty = skip_empty
          @min_length = min_length
        end

        def each_unit
          return to_enum(:each_unit) unless block_given?

          units_from_source.each do |unit|
            next if @skip_empty && unit.text.strip.empty?
            next if unit.text.strip.length < @min_length

            yield unit
          end
        end

        private def units_from_source
          # Parse YAML frontmatter before stripping it — Inkmark mis-parses
          # the `---` block as a setext H2, collapsing the whole document.
          fm = parse_frontmatter(@source)
          body_source = @source.sub(/\A---\n.*?\n---\n?/m, "")

          # Inkmark.chunks_by_heading already emits a heading: nil chunk for
          # any content before the first ATX heading — including the entire
          # body when a document has no headings at all (see legacy
          # MarkdownLoader's history: a separate hand-rolled preamble
          # extraction duplicated this content once, verified live).
          Inkmark.chunks_by_heading(body_source).map { |chunk| build_unit(chunk, fm) }
        end

        # rubocop:disable Metrics/MethodLength -- one Types::Unit literal; every metadata key
        # is a distinct fact Inkmark's chunk carries, not padding.
        private def build_unit(chunk, frontmatter)
          preamble = chunk[:heading].nil?

          Types::Unit.new(
            document_id: "#{@file_id}##{preamble ? 'preamble' : chunk[:id]}",
            text: clean_text(chunk[:content]),
            heading: chunk[:heading],
            metadata: {
              "file_id" => @file_id,
              "heading_level" => preamble ? nil : chunk[:level],
              "heading_slug" => chunk[:id],
              "byte_range" => chunk[:byte_range],
              "frontmatter" => frontmatter,
            }
          )
        end

        private def parse_frontmatter(source)
          match = source.match(/\A---\n(.*?)\n---\n?/m)
          return nil unless match

          require "yaml"
          YAML.safe_load(match[1], permitted_classes: [Time, Date, Symbol])
        rescue
          nil
        end

        # Render markdown to clean prose using Inkmark's AST pipeline and
        # PragmaticTokenizer for token-level normalisation.
        # one linear pipeline (markdown -> HTML -> strip tags -> decode entities -> paragraph
        # split -> tokenize), ported from legacy verbatim; each step is one line, splitting
        # them into separate methods would just relocate, not reduce, the same five sequential
        # transformations.
        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        private def clean_text(markdown)
          return "" if markdown.nil? || markdown.strip.empty?

          result = markdown.dup
          result.sub!(/\A---\n.*?\n---\n/m, "")
          return "" if result.strip.empty?

          # Inkmark renders to HTML — all markdown structure (bold, italic,
          # links, images, list markers, heading markers) handled at AST level.
          html = Inkmark.new(result, options: { syntax_highlight: false }).to_html

          # Drop fenced code blocks — identifiers corrupt POS/dependency parses.
          html.gsub!(%r{<pre><code[^>]*>.*?</code></pre>}m, " ")

          # Strip remaining HTML tags.
          prose = html.gsub(/<[^>]+>/, " ")

          # Decode HTML entities.
          HTML_ENTITIES.each { |entity, char| prose.gsub!(entity, char) }
          prose.gsub!(/&[a-z#0-9]+;/, " ")

          # Collapse whitespace, split into paragraphs.
          paragraphs = prose.tr("\t", " ").split("\n").map(&:strip).reject(&:empty?)

          return "" if paragraphs.empty?

          # Normalise each paragraph through PragmaticTokenizer.
          cleaned = paragraphs.map { |para| normalise_paragraph(para) }.reject(&:empty?)

          cleaned.join("\n\n")
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

        # Tokenise a prose paragraph and rejoin with natural spacing.
        # PragmaticTokenizer separates punctuation as distinct tokens;
        # CLOSING_PUNCT tokens reattach without a leading space.
        private def normalise_paragraph(para)
          tokens = PragmaticTokenizer::Tokenizer.new(TOKENIZER_OPTIONS).tokenize(para)
          return "" if tokens.empty?

          tokens.each_with_object([]) do |tok, buf|
            buf << if buf.empty? || CLOSING_PUNCT.include?(tok)
              tok
            else
              " #{tok}"
            end
          end.join.strip
        end
      end
    end
  end
end
