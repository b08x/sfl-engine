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
    # rubocop:disable Metrics/ClassLength -- one flat per-file coordination flow
    # (classify -> dispatch -> review-queue fallback) whose length the todo budget
    # already tracked at 101; the two registered loader source_types add one small
    # resolution seam (constant + dispatch_catalog_loader), not a new responsibility,
    # same trade-off SubtitleSource documents for its three format grammars.
    class Orchestrator
      # First N bytes read from each file for classifier/loader-drafter
      # sampling — keeps the LLM call cheap regardless of file size (see
      # the design doc's Data Flow section). Start as a constant, tune
      # later against real large-file corpora.
      SAMPLE_BYTES = 4096

      # Registered deterministic source_types (features/registration.feature)
      # resolved straight to their Core::Loaders::Catalog factory name.
      CATALOG_LOADER_SOURCE_TYPES = { "transcription" => :transcription, "vault_image_meta" => :image_meta }.freeze

      # Below this, a classifier verdict is treated the same as "no
      # confident match" even when format/mode are both present. Start as
      # a constant, tune later (design doc's Open Questions).
      CONFIDENCE_THRESHOLD = 0.6

      # Failures #process records against one file instead of ending the run.
      FILE_ERRORS = [Analysis::Error, Core::Loaders::Error, Core::Ports::SectionRegistry::ConflictError, Store::Error, SystemCallError].freeze

      # rubocop:disable Metrics/ParameterLists -- five collaborators (two dispatch targets, the
      # classifier, the drafter, the review repo) plus logger, matching this codebase's per-class
      # DI convention (see LLM::Engine#initialize), plus store:, forwarded to every dispatch so a
      # stored ingest persists clauses and records documents and sections through the pipeline's
      # SectionRegistry.
      def initialize(
        conversation_engine:, kb_source:, classifier:, loader_drafter:, review_repo:,
        logger: Core::Ports::Null::Logger.new, store: false, loaders: nil
      )
        # rubocop:enable Metrics/ParameterLists
        @conversation_engine = conversation_engine
        @kb_source = kb_source
        @classifier = classifier
        @loader_drafter = loader_drafter
        @review_repo = review_repo
        @logger = logger
        @store = store
        # nil builds the default catalog registry — the two registered
        # source_types' factories (SFL-ING-02's "resolved by name at boot").
        @loaders = loaders || Core::Registry.new.tap { |r| Core::Loaders::Catalog.register_into(r) }
      end

      # The path is expanded to an absolute path here, once, because each file's path_hint is
      # its document_key and the seed of its section ids: `notes`, `./notes` and the absolute
      # path must name the same document, or a re-ingest duplicates every clause (fact 17).
      #
      # @param path [String] a single file, or a directory walked recursively
      # @return [Hash{dispatched:, review_entries:, drafted:}]
      def run(path)
        counts = { dispatched: 0, review_entries: 0, drafted: 0 }
        corpus = Core::Ports::Adapters::FilesystemCorpusSource.new(File.expand_path(path))
        corpus.each_ref do |ref|
          process(ref.path_hint, counts)
        end
        logger.info("ingest run complete", **counts)
        counts
      end

      attr_reader :conversation_engine, :kb_source, :classifier, :loader_drafter, :review_repo, :logger, :loaders
      private :conversation_engine, :kb_source, :classifier, :loader_drafter, :review_repo, :logger, :loaders

      # One file's failure must not take the rest of the run down with it — same F11
      # partial-failure-isolation principle SFL::CLI.run_conversation's own per-file rescue
      # already applies (lib/sfl/cli.rb:225-233). SystemCallError covers the raw File.read call
      # in #classify (a file vanishing or losing permissions mid-walk,
      # e.g. a live filesystem being ingested concurrently with other writers) — without it, one
      # such file crashes the entire run instead of being isolated like every other failure mode
      # here (found by SIFT audit of the CLI wiring that first exercises a real directory walk).
      private def process(file, counts)
        return if review_repo.resolved?(file)

        classification = classify(file)
        dispatch_or_review(file, classification, counts)
      rescue *FILE_ERRORS => e
        logger.error("ingest failed", file:, error_class: e.class, error_message: e.message)
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
        ref = Core::Refs::FileRefBuilder.call(file)
        source_type = classification[:source_type]
        return dispatch_catalog_loader(ref, source_type) if CATALOG_LOADER_SOURCE_TYPES.key?(source_type)

        case classification[:mode]
        when "conversation" then dispatch_conversation(ref, classification)
        when "documentation" then dispatch_documentation(ref)
        when "knowledge_base" then kb_source.analyze(ref, store: @store)
        end
      end

      # The registered source_types resolve to their catalog loader factory; the
      # loader — an ordinary #each_unit source — is driven by the conversation
      # engine. Loaders::Error for content that does not match its classified
      # name is isolated per file by #process, like every other dispatch.
      private def dispatch_catalog_loader(ref, source_type)
        loader = loaders.resolve!(CATALOG_LOADER_SOURCE_TYPES.fetch(source_type), ref:)
        conversation_engine.analyze(loader, label: ref.name, store: @store)
      end

      private def dispatch_conversation(ref, classification)
        source = Analysis::ConversationSource.new(
          ref, source_type: classification[:source_type] || classification[:format]
        )
        conversation_engine.analyze(source, label: ref.name, store: @store)
      end

      private def dispatch_documentation(ref)
        conversation_engine.analyze(Analysis::DocumentationSource.new(single_ref: ref), label: ref.name, store: @store)
      end

      private def enqueue_low_confidence(file, classification)
        review_repo.enqueue(
          path: file, status: "low_confidence_mode", format: classification[:format], mode: classification[:mode],
          confidence: classification[:confidence], reasoning: classification[:reasoning]
        )
      end

      private def draft_or_record_failure(file, classification, counts)
        # Reuses the sample #classify already read instead of re-reading the same bytes:
        # this branch is only reachable via #classify_via_llm, whose merge(sample:)
        # sets :sample unconditionally, so no re-read guard is needed.
        sample = classification[:sample]
        draft = loader_drafter.draft(sample, file)
        enqueue_drafted(file, classification, draft)
        counts[:drafted] += 1
      rescue LoaderDrafter::Error => e
        logger.warn("loader draft failed", file:, error_message: e.message)
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
      # rubocop:enable Metrics/ClassLength
    end
  end
end
