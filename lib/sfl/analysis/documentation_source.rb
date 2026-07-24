# frozen_string_literal: true

module SFL
  module Analysis
    # Turns a markdown file, a PDF, or a directory of both into the
    # Core::Loaders::Source duck Analysis::Engine drives — delegating to
    # the Phase 1 MarkdownSource/PdfSource loaders per file and
    # flat-mapping their Units, rather than re-deriving section/heading
    # parsing here. Ported from legacy's DocumentationAnalyzer#load_sections
    # (directory-or-file glob dispatch) and its section -> "speaker"
    # (= heading) / fallback-annotation review-queue policy.
    #
    # ChunkArtifactDetector wiring: PDF chunking (Core::Loaders::PdfSource)
    # splits a document into arbitrary character-count chunks, unlike
    # markdown's heading-scoped sections — a real sentence can straddle
    # that split and get compiled as two ambiguous fragments, each
    # silently defaulting to 0.5 tenor/modality. This class tracks, as
    # #each_unit yields, which contiguous pairs of units came from the
    # same PDF file (`#chunk_boundaries`) — the generic post-compile hook
    # Engine#build_result calls on any source that implements it (see
    # ConversationSource's #review_entry/#extra_metadata for the same
    # established "Source answers a policy question, Engine acts on it
    # generically" pattern; this is the third hook in that family). All
    # PDF-chunk-specific bookkeeping lives here; Engine only knows "a
    # source can hand me flat clause-index boundaries." Markdown sections
    # are chunked by heading — a semantically real boundary — so a
    # pure-markdown run never records a pdf_chunk pair and
    # #chunk_boundaries always returns [], which means the detector never
    # runs on it: by construction, not by a content heuristic.
    class DocumentationSource
      include Core::Loaders::Source

      MIN_CLAUSE_THRESHOLD = 30

      # @param path [String] a .md/.pdf file, or a directory containing them
      def initialize(path)
        @path = path.to_s
        @unit_chunks = []
      end

      def each_unit(&)
        return to_enum(:each_unit) unless block_given?

        @unit_chunks = []
        files.each do |file|
          pdf_chunk = pdf?(file)
          loader_for(file).each_unit do |unit|
            @unit_chunks << { file_id: unit.metadata["file_id"], pdf_chunk: }
            yield unit
          end
        end
      end

      # Engine's generic post-compile hook (Engine#build_result calls this
      # only when the source responds to it — ConversationSource does
      # not). `turns` is one compiled Core::Types::ConversationTurn per
      # unit #each_unit yielded, in the same order, so a running clause
      # offset lines each `@unit_chunks` adjacency up with the flat
      # clause-index space ChunkArtifactDetector.detect expects.
      # @param turns [Array<Core::Types::ConversationTurn>]
      # @return [Array<Integer>] flat clause-array boundary indices where
      #   two contiguous same-file PDF chunks meet; [] for anything else
      #   (markdown-only runs, single-file PDFs never split, files that
      #   don't share a file_id).
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- one running-offset
      # walk over adjacent unit pairs, ported verbatim from legacy's #pdf_chunk_boundaries; the `&.`s
      # are the only branching, each independently necessary (turns can be shorter than @unit_chunks
      # when Engine's compile loop stops early).
      def chunk_boundaries(turns)
        return [] if @unit_chunks.size < 2

        boundaries = []
        offset = turns.first&.clauses&.size || 0

        @unit_chunks.each_cons(2).with_index(1) do |(prev, nxt), idx|
          boundaries << offset if contiguous_pdf_chunk?(prev, nxt)
          offset += turns[idx]&.clauses&.size || 0
        end

        boundaries
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # DocumentationAnalyzer's policy: enqueue only when the compiled
      # section actually produced a non-trusted (fallback/stub) clause —
      # unlike ConversationSource's audio-modality gate, this inspects the
      # compiled output, not just the input.
      # rubocop:disable Lint/UnusedMethodArgument -- unit stays for the shared Source#review_entry contract
      def review_entry(unit:, clauses:)
        # rubocop:enable Lint/UnusedMethodArgument
        untrusted = clauses.any? { |c| !Core::Types::TRUSTED_ANNOTATION_SOURCES.include?(c.interpersonal.annotation_source) }
        return nil unless untrusted

        {
          modality: "text",
          reason: "fallback_annotation",
          generated_text: clauses.map(&:text).join(" "),
          source_type: "vault_document",
        }
      end

      # Source-specific metadata additions, ported from
      # DocumentationAnalyzer#build_result's metadata Hash.
      def extra_metadata(turns)
        total_clauses = turns.sum { |t| t.clauses.size }
        {
          unit_label: "Section",
          actor_label: "Section",
          actors_list_label: "Headings",
          id_label: "document_id",
          clause_count: total_clauses,
          low_confidence: total_clauses < MIN_CLAUSE_THRESHOLD,
          low_confidence_threshold: MIN_CLAUSE_THRESHOLD,
        }
      end

      private def files
        File.directory?(@path) ? Dir.glob(File.join(@path, "**", "*.{md,pdf}")) : [@path]
      end

      private def loader_for(file)
        pdf?(file) ? Core::Loaders::PdfSource.new(file) : Core::Loaders::MarkdownSource.new(file)
      end

      private def pdf?(file) = File.extname(file).casecmp(".pdf").zero?

      private def contiguous_pdf_chunk?(prev, nxt)
        prev[:pdf_chunk] && nxt[:pdf_chunk] && prev[:file_id] == nxt[:file_id]
      end
    end
  end
end
