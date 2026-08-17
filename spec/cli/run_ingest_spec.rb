# frozen_string_literal: true

require "spec_helper"
require "dspy"

RSpec.describe SFL::CLI do
  let(:lm_factory) { instance_double(SFL::LLM::LMFactory) }
  let(:classifier) { instance_double(SFL::LLM::Classifier) }
  let(:loader_drafting_lm) { instance_double(DSPy::LM) }
  let(:boot_result) do
    SFL::Boot::Result.new(
      db: instance_double(Sequel::Database), llm_config: instance_double(SFL::LLM::Config), lm_factory:,
      embedder: instance_double(SFL::LLM::Embedder), classifier:, pass1_command: nil, spacy_model: "en_core_web_sm"
    )
  end
  let(:conversation_engine) { instance_double(SFL::Analysis::Engine) }
  let(:kb_source) { instance_double(SFL::Analysis::KnowledgeBaseSource) }
  let(:loader_drafter) { instance_double(SFL::Ingest::LoaderDrafter) }
  let(:review_repo) { instance_double(SFL::Store::PgIngestReviewRepository) }
  let(:orchestrator) { instance_double(SFL::Ingest::Orchestrator) }

  before do
    allow(SFL::Core::PassOne::SpacySidecarParser).to receive(:new)
      .and_return(instance_double(SFL::Core::PassOne::SpacySidecarParser))
    allow(SFL::Boot).to receive(:call).and_return(boot_result)
    allow(SFL::LLM::EngineBuilder).to receive(:call).and_return(instance_double(SFL::LLM::Engine))
    allow(SFL::Analysis::Engine).to receive(:new).and_return(conversation_engine)
    allow(SFL::Analysis::KnowledgeBaseSource).to receive(:new).and_return(kb_source)
    allow(lm_factory).to receive(:for).with(:loader_drafting).and_return(loader_drafting_lm)
    allow(SFL::Ingest::LoaderDrafter).to receive(:new).and_return(loader_drafter)
    allow(SFL::Store::PgIngestReviewRepository).to receive(:new).and_return(review_repo)
    allow(SFL::Ingest::Orchestrator).to receive(:new).and_return(orchestrator)
    allow(orchestrator).to receive(:run).and_return({ dispatched: 3, review_entries: 2, drafted: 1 })
    allow($stdout).to receive(:puts)
  end

  describe ".run_ingest" do
    let(:options) { { output_dir: "./out", disable_tracing: false } }

    it "boots with require_llm: true" do
      described_class.run_ingest("./inbox", options)

      expect(SFL::Boot).to have_received(:call).with(require_llm: true, require_tracing: true)
    end

    it "honors --disable-tracing" do
      described_class.run_ingest("./inbox", options.merge(disable_tracing: true))

      expect(SFL::Boot).to have_received(:call).with(require_llm: true, require_tracing: false)
    end

    it "builds the Orchestrator with the classifier, loader_drafter, review_repo, and dispatch targets" do
      described_class.run_ingest("./inbox", options)

      expect(SFL::Ingest::LoaderDrafter).to have_received(:new).with(lm: loader_drafting_lm)
      expect(SFL::Store::PgIngestReviewRepository).to have_received(:new).with(boot_result.db)
      expect(SFL::Ingest::Orchestrator).to have_received(:new).with(
        conversation_engine:, kb_source:, classifier:, loader_drafter:, review_repo:, logger: anything
      )
    end

    it "calls Orchestrator#run with the input path" do
      described_class.run_ingest("./inbox", options)

      expect(orchestrator).to have_received(:run).with("./inbox")
    end

    it "prints a human-readable summary of the returned counts" do
      described_class.run_ingest("./inbox", options)

      expect($stdout).to have_received(:puts).with(/dispatched/i)
      expect($stdout).to have_received(:puts).with(/3/)
      expect($stdout).to have_received(:puts).with(/2/)
      expect($stdout).to have_received(:puts).with(/1/)
    end
  end
end
