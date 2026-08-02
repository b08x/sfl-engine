# frozen_string_literal: true

require "spec_helper"
require "ruby_llm"

RSpec.describe SFL::API::Context do
  describe ".build" do
    # Regression test for a live-verified boot bug (2026-08-02): this used to be a bare
    # `SFL::API.build_context` module method, defined as a side effect of Zeitwerk autoloading
    # this file -- which only happens once something references the `Context` constant.
    # config.ru's `SFL::API.build_context(boot_result)` is/was the ONLY call site anywhere in
    # this codebase, so nothing ever triggered that autoload first, and the HTTP API server
    # raised NoMethodError on every real boot. Attaching the factory to `Context` itself
    # (`Context.build`) means the very reference that calls it is what loads this file, so the
    # method is guaranteed to exist independent of what else has run first -- this spec's only
    # job is to prove `Context.build` actually returns a fully-wired Context, not a NoMethodError.
    it "wires a fully-populated Context from a Boot::Result" do
      allow(SFL::Core::PassOne::SpacySidecarParser).to receive(:new)
        .and_return(instance_double(SFL::Core::PassOne::SpacySidecarParser))
      chat = instance_double(RubyLLM::Chat)
      chat_factory = instance_double(SFL::LLM::ChatFactory)
      allow(chat_factory).to receive(:for).and_return(chat)
      boot_result = SFL::Boot::Result.new(
        db: SFL::Store::StoreTestDb.db, llm_config: instance_double(SFL::LLM::Config), chat_factory:,
        embedder: instance_double(SFL::LLM::Embedder), pass1_command: nil, pass1_env: nil,
        spacy_model: "en_core_web_sm", api_debug_errors: false, api_cors_origins: []
      )

      ctx = described_class.build(boot_result)

      expect(ctx).to be_a(described_class)
      expect(ctx.pipeline).to be_a(SFL::Core::Pipeline)
      expect(ctx.retriever).to be_a(SFL::Store::PgHybridRetriever)
      expect(ctx.synthesizer).to be_a(SFL::Retrieval::ContextSynthesizer)
      expect(ctx.clause_store).to be_a(SFL::Store::PgClauseStore)
      expect(ctx.review_queue_repo).to be_a(SFL::Store::PgReviewQueueRepository)
      expect(ctx.annotation_review_repo).to be_a(SFL::Store::PgAnnotationReviewRepository)
      expect(ctx.pass_two).to be_a(SFL::LLM::Engine)
      expect(ctx.clause_review_service).to be_a(SFL::API::ClauseReviewService)
    end
  end
end
