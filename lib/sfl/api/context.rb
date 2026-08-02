# frozen_string_literal: true

module SFL
  module API
    # Everything Server needs, pre-wired — mirrors Boot::Result's role for
    # the CLI, but bundles fully-constructed collaborators (not raw
    # db/config) since every route hits exactly one of these, never raw SQL.
    #
    # - `pipeline`: Core::Pipeline, built via CLI.build_pipeline so the API
    #   shares the exact same Pass 1/Pass 2/store wiring the CLI uses —
    #   POST /pipeline/compile and the review-queue "edit"/clause "re_annotated"
    #   recompile paths all go through this one instance.
    # - `retriever`: Store::PgHybridRetriever, for POST /retrieve.
    # - `synthesizer`: Retrieval::ContextSynthesizer, for POST /synthesize.
    # - `clause_store`: Store::PgClauseStore, for GET /clauses and the
    #   accepted/rejected/re_annotated branches of POST /clauses/:id/review.
    # - `review_queue_repo`: Store::PgReviewQueueRepository (content-review
    #   queue: GET/POST /review-queue*).
    # - `annotation_review_repo`: Store::PgAnnotationReviewRepository
    #   (clause-review audit trail: GET /clauses/review-queue, POST
    #   /clauses/:id/review's accepted/rejected/re_annotated branches).
    # - `pass_two`: Core::Ports::Annotator, for the single-clause re_annotated
    #   path (Pass 2 only, no full Pipeline#compile — see ClauseReviewService#reannotate).
    # - `clause_review_service`: ClauseReviewService, for POST /clauses/:id/review
    #   (issue #2 — re-annotation write + audit record in one transaction).
    Context = Struct.new(
      :pipeline, :retriever, :synthesizer, :clause_store, :review_queue_repo,
      :annotation_review_repo, :pass_two, :clause_review_service,
      keyword_init: true
    )

    class Context
      # Composes a Context from a Boot::Result — config.ru's one call site.
      # Reuses CLI.build_pipeline/CLI.build_collaborators rather than
      # duplicating that wiring a second time (the same T4 "one factory, not
      # four near-identical copies" fix CLI.build_pipeline itself exists
      # for). `store: true` in the options passed to build_pipeline wires a
      # real PgEmbeddingStore/embedder (not the Null doubles a pass1-only/
      # no-store CLI run would get) — POST /pipeline/compile lets a caller
      # request `embed: true` per request, so the pipeline must be able to
      # honor that. `resume: false` keeps the cache Null — API requests
      # aren't a resumable multi-turn CLI run.
      #
      # A method ON Context (not a bare `SFL::API.build_context` module
      # method, which is what this used to be) deliberately: live-verified
      # 2026-08-02 that config.ru is the only call site anywhere in this
      # codebase, so `SFL::API.build_context(...)` was calling a method that
      # only existed if something ELSE had already referenced
      # `SFL::API::Context` and triggered Zeitwerk to autoload this file —
      # which nothing did. The HTTP API had never actually booted. Defining
      # this as `Context.build` instead means the very reference that calls
      # it (`SFL::API::Context.build(...)`) is what triggers Zeitwerk to
      # load this file, so the method is guaranteed to exist by the time
      # it's called, independent of what else has run first.
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- one flat collaborator-wiring
      # sequence, each line building exactly one Context field.
      def self.build(boot_result)
        logger, instrumenter, breaker = CLI.build_collaborators
        pipeline = CLI.build_pipeline(boot_result, { store: true, resume: false }, breaker:, instrumenter:, logger:)
        pass_two = LLM::EngineBuilder.call(
          config: boot_result.llm_config, chat_factory: boot_result.chat_factory, breaker:, instrumenter:, logger:
        )
        clause_store = Store::PgClauseStore.new(boot_result.db)
        annotation_review_repo = Store::PgAnnotationReviewRepository.new(boot_result.db)

        new(
          pipeline:,
          retriever: Store::PgHybridRetriever.new(db: boot_result.db, embedder: boot_result.embedder),
          synthesizer: Retrieval::ContextSynthesizer.new(
            retriever: Store::PgHybridRetriever.new(db: boot_result.db, embedder: boot_result.embedder),
            chat: boot_result.chat_factory.for(:context_synthesis), breaker:, instrumenter:, logger:
          ),
          clause_store:,
          review_queue_repo: Store::PgReviewQueueRepository.new(boot_result.db),
          annotation_review_repo:,
          pass_two:,
          clause_review_service: ClauseReviewService.new(db: boot_result.db, clause_store:, annotation_review_repo:,
            pass_two:)
        )
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    end
  end
end
