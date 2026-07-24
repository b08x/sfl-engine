# frozen_string_literal: true

require "time"

module SFL
  module Analysis
    # Analyzes a directory or file set as a knowledge base corpus rather
    # than as a conversation: each document section becomes a
    # Core::Types::KnowledgeArtifact with a content_type classification,
    # quality_score, and migration_action recommendation, assembled into
    # a Core::Types::KnowledgeBaseReport. Deliberately its own entry point
    # rather than a Core::Loaders::Source driven through Engine#analyze —
    # KnowledgeBaseReport's shape (artifacts/migration_manifest/
    # content_type_distribution/quality_distribution/staleness_flags) has
    # nothing in common with AnalysisResult's turn-centric one, so forcing
    # it through Engine's compile loop would only relocate this class's
    # own loop into Engine, not remove it (this was scoped out explicitly
    # in an earlier pass on this card, not an oversight).
    #
    # Reuses the same Phase 1 Core::Loaders::Source ducks Analysis::
    # DocumentationSource already reuses (MarkdownSource/PdfSource), plus
    # CanvasSource and (opt-in) ImageSource — one loader instance per
    # file, #each_unit walked directly rather than re-deriving section
    # parsing here.
    #
    # Scoped to .md/.pdf/.canvas/images: legacy additionally routed
    # .docx/.xlsx/.pptx/.html through PdfLoader on the claim that
    # kreuzberg auto-detects format from the file itself, independent of
    # loader naming. Core::Loaders::PdfSource (this codebase's port) has
    # only ever been exercised against real .pdf fixtures — extending its
    # use to those four other extensions here would be an unverified
    # assumption about kreuzberg's dispatch, not a verified port; a later
    # slice can widen TEXT_EXTENSIONS once a spec fixture proves it out.
    #
    # ImageSource DI: unlike legacy's ImageLoader.new(path, vision_model:)
    # (which resolved its own chat internally from a bare model-id
    # string), Core::Loaders::ImageSource takes an injected `chat:`
    # (decision 8) — this class propagates that same correction via its
    # own `chat:` constructor kwarg instead of a `vision_model:` string.
    #
    # Storage note: like Analysis::Engine (first Phase 3 slice), this
    # class does not take a clause_repo/clause_store — Pipeline#persist
    # (via PgClauseStore#replace_document) already deletes+reinserts
    # atomically, so there is no separate "delete before compile" step
    # left for a caller to own.
    #
    # rubocop:disable Metrics/ClassLength -- one use case (analyze) with its file-walk/compile/
    # classify/score/assess loop plus the report-assembly aggregations legacy's
    # KnowledgeBaseAnalyzer kept in a single class; each already its own small private method.
    class KnowledgeBaseSource
      include Aggregations

      TEXT_EXTENSIONS = %w[.md .canvas .pdf].freeze
      IMAGE_EXTENSIONS = Core::Loaders::ImageSource::SUPPORTED_EXTENSIONS
      STALENESS_MONTHS = 18
      LOW_QUALITY_THRESHOLD = 0.40 # matches QualityScorer's own "low" quality bucket cutoff

      # @param pipeline [Core::Pipeline]
      # @param review_queue_repo [Store::PgReviewQueueRepository, nil]
      # @param on_progress [#call, nil] called with { artifact_id:, total:, title:, source_file: }
      #   before each section is compiled
      # @param stop_requested [#call, nil] polled once per artifact; if it returns truthy the
      #   loop halts and a partial report is returned
      # @param analyze_images [Boolean] run vision description on image files (disabled by
      #   default — expensive)
      # @param chat [#ask, nil] a vision-capable RubyLLM::Chat (or compatible double), forwarded
      #   to Core::Loaders::ImageSource; required (raises otherwise) when analyze_images: true
      # rubocop:disable Metrics/ParameterLists -- six independently-injectable collaborators,
      # matching Engine#initialize's own house style (see its class comment).
      def initialize(
        pipeline:,
        review_queue_repo: nil,
        on_progress: nil,
        stop_requested: nil,
        analyze_images: false,
        chat: nil
      )
        # rubocop:enable Metrics/ParameterLists
        raise ArgumentError, "chat: is required when analyze_images: true" if analyze_images && chat.nil?

        @pipeline = pipeline
        @review_queue_repo = review_queue_repo
        @on_progress = on_progress
        @stop_requested = stop_requested
        @analyze_images = analyze_images
        @chat = chat
        @classifier = ContentTypeClassifier.new
        @scorer = QualityScorer.new
        @assessor = MigrationAssessor.new
      end

      # @param path [String] a file or directory
      # @param store [Boolean] persist clauses + embeddings
      # @param resume [Boolean] reuse cached Pass 2 results
      # @return [Core::Types::KnowledgeBaseReport]
      # rubocop:disable Metrics/MethodLength -- one flat KnowledgeBaseReport literal plus the
      # three-step file-walk/compile/assess pipeline that builds it; every step is already its
      # own private method call, ported verbatim from legacy's own #analyze.
      def analyze(path, store: false, resume: false)
        @resume = resume

        tuples = load_all_units(path.to_s)
        total = tuples.size

        artifacts, skipped = compile_artifacts(tuples, total, store)
        manifest = build_manifest(artifacts)
        artifacts = backfill_migration(artifacts, manifest)

        Core::Types::KnowledgeBaseReport.new(
          metadata: report_metadata(path, artifacts, tuples, store, skipped),
          artifacts:,
          migration_manifest: manifest,
          content_type_distribution: type_distribution(artifacts),
          quality_distribution: quality_buckets(artifacts),
          staleness_flags: staleness_flags(artifacts)
        )
      end
      # rubocop:enable Metrics/MethodLength

      # rubocop:disable Metrics/MethodLength -- one compile loop with a stop/progress/rescue
      # sequence per unit, ported verbatim from legacy's #analyze loop; each step is already its
      # own private method call.
      private def compile_artifacts(tuples, total, store)
        skipped = []
        artifacts = tuples.each_with_index.with_object([]) do |((unit, file, mtime, source_type), idx), acc|
          break acc if @stop_requested&.call

          artifact_id = idx + 1
          @on_progress&.call(artifact_id:, total:, title: unit_title(unit), source_file: file)

          begin
            acc << compile_artifact(unit, artifact_id, store, file_meta: { source_file: file, mtime:, source_type: })
          rescue => e
            # Same degradation ladder as Pipeline#compile: one malformed vault file (bad
            # frontmatter, unparseable content) must not abort a whole-corpus run — a
            # Date-typed title at artifact 10 once killed a 1295-artifact batch and all its
            # prior LLM spend (a real incident, not hypothetical). Interrupts (Ctrl+C) are not
            # StandardError and still abort.
            skipped << { artifact_id:, source_file: file, error: e.message }
            warn "[WARN] KB artifact #{artifact_id} (#{file}) skipped: #{e.message}"
          end
        end
        [artifacts, skipped]
      end
      # rubocop:enable Metrics/MethodLength

      # rubocop:disable Metrics/MethodLength -- one flat-mapped file walk plus a per-file rescue,
      # ported verbatim from legacy's own #load_all_sections; the rescue is what makes a single
      # unreadable file (permissions, corrupt binary) non-fatal for the rest of the corpus.
      private def load_all_units(path)
        collect_files(path).flat_map do |file|
          ext = File.extname(file).downcase
          mtime = File.mtime(file)
          loader = loader_for(file, ext)
          next [] unless loader

          source_type = source_type_for(ext)
          loader.each_unit.map { |unit| [unit, file, mtime, source_type] }
        rescue => e
          warn "[WARN] KnowledgeBaseSource: skipping #{file}: #{e.message}"
          []
        end
      end
      # rubocop:enable Metrics/MethodLength

      private def collect_files(path)
        extensions = TEXT_EXTENSIONS + (@analyze_images ? IMAGE_EXTENSIONS : [])

        if File.directory?(path)
          Dir.glob(File.join(path, "**", "*"))
            .select { |f| File.file?(f) && extensions.include?(File.extname(f).downcase) }
            .sort
        else
          [path]
        end
      end

      private def loader_for(file, ext)
        case ext
        when ".md" then Core::Loaders::MarkdownSource.new(file)
        when ".canvas" then Core::Loaders::CanvasSource.new(file)
        when ".pdf" then Core::Loaders::PdfSource.new(file)
        when *IMAGE_EXTENSIONS then Core::Loaders::ImageSource.new(file, chat: @chat)
        end
      end

      private def source_type_for(ext)
        case ext
        when ".md" then "vault_markdown"
        when ".canvas" then "vault_canvas"
        when ".pdf" then "vault_pdf"
        when *IMAGE_EXTENSIONS then "vault_image"
        else "vault_document"
        end
      end

      private def unit_title(unit)
        frontmatter = unit.metadata["frontmatter"]
        # Frontmatter values are typed by YAML, not by us: an unquoted `title: 2026-06-08`
        # parses as a Date — the same coercion legacy's #compile_artifact already applies to
        # tags, guarding artifact assembly the same way here.
        fm_title = frontmatter&.dig("title")&.to_s
        return fm_title unless fm_title.nil? || fm_title.strip.empty?

        unit.heading || unit.document_id
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      # -- one flat KnowledgeArtifact literal plus its supporting compile/classify/score calls,
      # ported verbatim from legacy's own #compile_artifact.
      private def compile_artifact(unit, artifact_id, store, file_meta:)
        source_file, mtime, source_type = file_meta.values_at(:source_file, :mtime, :source_type)
        frontmatter = unit.metadata["frontmatter"]
        last_updated = parse_last_updated(frontmatter&.dig("last updated") || frontmatter&.dig("last_updated")) || mtime
        tags = Array(frontmatter&.dig("tags")).map(&:to_s)

        clauses = unwrap(
          @pipeline.compile(unit.text, document_id: unit.document_id, store:, embed: store,
            resume: @resume), unit.document_id
        )

        content_type = @classifier.classify(section: unit, clauses:, frontmatter:)
        quality_score = @scorer.score(clauses:, last_updated:)

        llm_count = clauses.count { |c| c.interpersonal.annotation_source == "llm" }
        human_count = clauses.count { |c| c.interpersonal.annotation_source == "human" }

        if store
          enqueue_review(unit.document_id, source_file, source_type, content_type, unit.text, clauses,
            quality_score)
        end

        Core::Types::KnowledgeArtifact.new(
          artifact_id:,
          title: unit_title(unit),
          source_file:,
          section_path: unit.heading,
          content_type:,
          quality_score:,
          migration_action: :review, # overwritten after the assessment pass
          migration_reason: "",
          tags:,
          last_updated:,
          clauses:,
          avg_tenor: mean(clauses.map { |c| c.interpersonal.tenor }),
          avg_modality: mean(clauses.map { |c| c.interpersonal.modality_weight }),
          dominant_mood: clauses.map { |c| c.interpersonal.mood }.tally.max_by { |_, n| n }&.first || "declarative",
          process_types: clauses.map { |c| c.ideational.process_type }.tally,
          annotation_coverage: {
            llm: llm_count, human: human_count, fallback: clauses.size - llm_count - human_count, total: clauses.size
          }
        )
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      private def unwrap(result, document_id)
        result.value_or { |failure| raise Error, "compile failed for #{document_id.inspect}: #{failure.inspect}" }
      end

      # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists -- seven independently-meaningful
      # review-queue fields, ported verbatim from legacy's own #enqueue_for_review; the
      # vault_image early-return is a real second, unrelated review policy, not padding.
      private def enqueue_review(document_id, source_file, source_type, content_type, generated_text, clauses,
        quality_score
      )
        return unless @review_queue_repo

        if source_type == "vault_image"
          @review_queue_repo.enqueue(
            document_id:, modality: "image", source_file:, generated_text:,
            reason: "image", source_type:, content_type:
          )
          return
        end

        reason = review_reason(clauses, quality_score)
        return unless reason

        @review_queue_repo.enqueue(
          document_id:, modality: "text", source_file:, generated_text:,
          reason:, source_type:, content_type:
        )
      end
      # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists

      private def review_reason(clauses, quality_score)
        if clauses.any? { |c| !Core::Types::TRUSTED_ANNOTATION_SOURCES.include?(c.interpersonal.annotation_source) }
          "fallback_annotation"
        elsif quality_score < LOW_QUALITY_THRESHOLD
          "low_quality_score"
        end
      end

      private def parse_last_updated(value)
        return nil unless value

        Time.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      private def build_manifest(artifacts)
        artifacts.map do |a|
          @assessor.assess(
            artifact_id: a.artifact_id, title: a.title, source_file: a.source_file,
            content_type: a.content_type, quality_score: a.quality_score
          )
        end
      end

      # Backfills migration_action/reason from the manifest into the artifacts so the artifact
      # structs are self-contained (report consumers don't need to cross-reference).
      private def backfill_migration(artifacts, manifest)
        manifest_index = manifest.to_h { |m| [m.artifact_id, m] }
        artifacts.map do |a|
          entry = manifest_index[a.artifact_id]
          a.new(migration_action: entry.action, migration_reason: entry.reason)
        end
      end

      # -- one flat KnowledgeBaseReport#metadata literal.
      private def report_metadata(path, artifacts, tuples, store, skipped)
        {
          source_path: path.to_s,
          analyzed_at: Time.now.iso8601,
          artifact_count: artifacts.size,
          file_count: tuples.map { |(_unit, file, _mtime, _source_type)| file }.uniq.size,
          images_analyzed: @analyze_images,
          store:,
          skipped_count: skipped.size,
          skipped:,
        }
      end
      private def type_distribution(artifacts)
        artifacts.group_by(&:content_type).transform_values(&:size)
      end

      private def quality_buckets(artifacts)
        {
          high: artifacts.count { |a| a.quality_score >= 0.65 },
          medium: artifacts.count { |a| a.quality_score >= 0.40 && a.quality_score < 0.65 },
          low: artifacts.count { |a| a.quality_score < 0.40 },
        }
      end

      private def staleness_flags(artifacts)
        cutoff = Time.now - (STALENESS_MONTHS * 30 * 24 * 60 * 60)
        artifacts.filter_map do |a|
          next unless a.last_updated && a.last_updated < cutoff

          { artifact_id: a.artifact_id, title: a.title, last_updated: a.last_updated.iso8601 }
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
