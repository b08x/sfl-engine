# frozen_string_literal: true

module SFL
  module Ingest
    # Coordinates one ingest run: walks a file or directory, classifies
    # each file (Ingest::DeterministicRules first, Core::Ports::Classifier
    # as fallback), and dispatches matches to the existing, unmodified
    # Analysis::Engine (conversation/documentation) or
    # Analysis::KnowledgeBaseSource — see the design doc's architecture
    # diagram (docs/superpowers/specs/2026-08-06-intelligent-ingest-layer-design.md)
    # for the full decision flow.
    #
    # Low-confidence and unrecognized-format files never get dispatched —
    # they're recorded via Store::PgIngestReviewRepository instead (F11
    # partial-failure isolation: one file's issue never halts the rest of
    # the run, same principle SFL::CLI.run_conversation's own per-file
    # rescue already applies).
    class Orchestrator
      # First N bytes read from each file for classifier/loader-drafter
      # sampling — keeps the LLM call cheap regardless of file size (see
      # the design doc's Data Flow section). Start as a constant, tune
      # later against real large-file corpora.
      SAMPLE_BYTES = 4096

      # Below this, a classifier verdict is treated the same as "no
      # confident match" even when format/mode are both present. Start as
      # a constant, tune later (design doc's Open Questions).
      CONFIDENCE_THRESHOLD = 0.6

      # rubocop:disable Metrics/ParameterLists -- five independently-injectable collaborators
      # (two dispatch targets, the classifier, the drafter, the review repo) plus logger,
      # matching this codebase's existing per-class DI convention (see LLM::Engine#initialize).
      def initialize(
        conversation_engine:, kb_source:, classifier:, loader_drafter:, review_repo:,
        logger: Core::Ports::Null::Logger.new
      )
        @conversation_engine = conversation_engine
        @kb_source = kb_source
        @classifier = classifier
        @loader_drafter = loader_drafter
        @review_repo = review_repo
        @logger = logger
      end
      # rubocop:enable Metrics/ParameterLists

      # @param path [String] a single file, or a directory walked recursively
      # @return [Hash{dispatched:, review_entries:, drafted:}]
      def run(path)
        counts = { dispatched: 0, review_entries: 0, drafted: 0 }
        files(path).each { |file| process(file, counts) }
        logger.info { "ingest run complete: #{counts}" }
        counts
      end

      attr_reader :conversation_engine, :kb_source, :classifier, :loader_drafter, :review_repo, :logger
      private :conversation_engine, :kb_source, :classifier, :loader_drafter, :review_repo, :logger

      private def files(path)
        return [path] unless File.directory?(path)

        Dir.glob(File.join(path, "**", "*")).select { |p| File.file?(p) }.sort
      end

      # One file's failure must not take the rest of the run down with it — same F11
      # partial-failure-isolation principle SFL::CLI.run_conversation's own per-file rescue
      # already applies (lib/sfl/cli.rb:225-233).
      private def process(file, counts)
        return if review_repo.resolved?(file)

        classification = classify(file)
        dispatch_or_review(file, classification, counts)
      rescue Analysis::Error, Core::Loaders::Error, Store::Error => e
        logger.error { "ingest failed for #{file}: #{e.class}: #{e.message}" }
        review_repo.enqueue(path: file, status: "draft_failed", reasoning: "Dispatch failed: #{e.message}")
        counts[:review_entries] += 1
      end

      private def classify(file)
        deterministic = DeterministicRules.classify(file)
        return deterministic if deterministic

        sample = File.read(file, SAMPLE_BYTES)
        classify_via_llm(sample, file)
      end

      private def classify_via_llm(sample, file)
        classifier.classify(sample, file).to_h.merge(sample:)
      end

      private def dispatch_or_review(file, classification, counts)
        if deterministic_or_confident?(classification)
          dispatch(file, classification)
          counts[:dispatched] += 1
        elsif classification[:format] && classification[:format] != "unknown"
          enqueue_low_confidence(file, classification)
          counts[:review_entries] += 1
        else
          draft_or_record_failure(file, classification, counts)
        end
      end

      # A deterministic match (no :confidence key at all) is always dispatched — its
      # confidence is definitionally 1.0, matching today's unchanged extension/JSON-key
      # dispatch behavior. A classifier verdict only dispatches at/above CONFIDENCE_THRESHOLD.
      private def deterministic_or_confident?(classification)
        return true unless classification.key?(:confidence)

        classification[:mode] && classification[:confidence] >= CONFIDENCE_THRESHOLD
      end

      private def dispatch(file, classification)
        case classification[:mode]
        when "conversation" then dispatch_conversation(file, classification)
        when "documentation" then dispatch_documentation(file)
        when "knowledge_base" then kb_source.analyze(file)
        end
      end

      private def dispatch_conversation(file, classification)
        source = Analysis::ConversationSource.new(
          file, source_type: classification[:source_type] || classification[:format]
        )
        conversation_engine.analyze(source, label: label_for(file))
      end

      private def dispatch_documentation(file)
        conversation_engine.analyze(Analysis::DocumentationSource.new(file), label: label_for(file))
      end

      private def label_for(file) = File.basename(file, ".*")

      private def enqueue_low_confidence(file, classification)
        review_repo.enqueue(
          path: file, status: "low_confidence_mode", format: classification[:format], mode: classification[:mode],
          confidence: classification[:confidence], reasoning: classification[:reasoning]
        )
      end

      private def draft_or_record_failure(file, classification, counts)
        # Reuses the sample #classify already read (this branch is only reachable via the
        # classifier fallback) instead of re-reading the same bytes; fallback guards the invariant.
        sample = classification[:sample] || File.read(file, SAMPLE_BYTES)
        draft = loader_drafter.draft(sample, file)
        enqueue_drafted(file, classification, draft)
        counts[:drafted] += 1
      rescue LoaderDrafter::Error => e
        logger.warn { "loader draft failed for #{file}: #{e.message}" }
        review_repo.enqueue(path: file, status: "draft_failed", reasoning: "Draft failed: #{e.message}")
        counts[:review_entries] += 1
      end

      private def enqueue_drafted(file, classification, draft)
        review_repo.enqueue(
          path: file, status: "loader_drafted", format: classification[:format],
          confidence: classification[:confidence], reasoning: classification[:reasoning],
          loader_path: draft[:loader_path], doc_path: draft[:doc_path]
        )
      end
    end
  end
end
