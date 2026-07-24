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
    # Deferred, not ported (flagged per this slice's brief rather than
    # half-ported): legacy's DocumentationAnalyzer also ran
    # ChunkArtifactDetector across PDF-chunk boundaries
    # (#flag_chunk_artifacts/#pdf_chunk_boundaries/#rebuild_turns_with_chunk_artifacts)
    # to mark clauses that straddle an arbitrary PDF chunk split as
    # "chunk_artifact" and exclude them from that turn's averages. That
    # logic is a composed post-processor over already-compiled turns —
    # the same category as the card's later "chunk-artifact detection...
    # as composed post-processors" bullet — so it is NOT ported here.
    # DocumentationSource-compiled turns from PDF input are therefore
    # honest about *not* screening for chunk-boundary artifacts yet; a
    # later slice wires ChunkArtifactDetector back in as one of Engine's
    # composed post-processing stages instead of duplicating it a second
    # time inside this Source.
    class DocumentationSource
      include Core::Loaders::Source

      MIN_CLAUSE_THRESHOLD = 30

      # @param path [String] a .md/.pdf file, or a directory containing them
      def initialize(path)
        @path = path.to_s
      end

      def each_unit(&)
        return to_enum(:each_unit) unless block_given?

        files.each do |file|
          loader_for(file).each_unit(&)
        end
      end

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
        File.extname(file).casecmp(".pdf").zero? ? Core::Loaders::PdfSource.new(file) : Core::Loaders::MarkdownSource.new(file)
      end
    end
  end
end
