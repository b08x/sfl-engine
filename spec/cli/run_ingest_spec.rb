# frozen_string_literal: true

require "spec_helper"
require "dspy"

RSpec.describe SFL::CLI do
  let(:lm_factory) { instance_double(SFL::LLM::LMFactory) }
  let(:classifier) { instance_double(SFL::LLM::Classifier) }
  let(:loader_drafting_lm) { instance_double(DSPy::LM) }
  let(:boot_result) do
    SFL::Boot::Result.new(
      db: instance_double(Sequel::Database), llm_config: instance_double(SFL::LLM::Config, header: {}), lm_factory:,
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
    allow(SFL::Boot).to receive_messages(call: boot_result, run_id: "run-7")
    allow(SFL::LLM::EngineBuilder).to receive(:call).and_return(instance_double(SFL::LLM::Engine))
    allow(SFL::Analysis::Engine).to receive(:new).and_return(conversation_engine)
    allow(SFL::Analysis::KnowledgeBaseSource).to receive(:new).and_return(kb_source)
    allow(lm_factory).to receive(:for).with(:loader_drafting).and_return(loader_drafting_lm)
    allow(SFL::Ingest::LoaderDrafter).to receive(:new).and_return(loader_drafter)
    allow(SFL::Store::PgIngestReviewRepository).to receive(:new).and_return(review_repo)
    allow(SFL::Ingest::Orchestrator).to receive(:new).and_return(orchestrator)
    allow(orchestrator).to receive(:run).and_return({ dispatched: 3, review_entries: 2, drafted: 1 })
    allow(SFL::Store::PgRunRepository).to receive(:new).with(boot_result.db)
      .and_return(SFL::Core::Ports::Fake::RunLog.new)
    allow(SFL::Store::PgSectionRegistry).to receive(:new).and_call_original
    allow(Thread).to receive(:new).and_return(instance_double(Thread, kill: nil))
    allow($stdout).to receive(:puts)
  end

  # The Fake::RunLog the stubbed PgRunRepository.new returns (the same object on every call).
  def run_log = SFL::Store::PgRunRepository.new(boot_result.db)

  describe ".run_ingest" do
    let(:options) { { output_dir: "./out", disable_tracing: false, collection: "inbox" } }

    it "boots with require_llm: true and checks the schema" do
      described_class.run_ingest("./inbox", options)

      expect(SFL::Boot).to have_received(:call).with(require_llm: true, require_tracing: true, require_schema: true)
    end

    it "honors --disable-tracing" do
      described_class.run_ingest("./inbox", options.merge(disable_tracing: true))

      expect(SFL::Boot).to have_received(:call).with(require_llm: true, require_tracing: false, require_schema: true)
    end

    it "builds the Orchestrator with the classifier, loader_drafter, review_repo, and dispatch targets" do
      described_class.run_ingest("./inbox", options)

      expect(SFL::Ingest::LoaderDrafter).to have_received(:new).with(lm: loader_drafting_lm)
      expect(SFL::Store::PgIngestReviewRepository).to have_received(:new).with(boot_result.db)
      expect(SFL::Ingest::Orchestrator).to have_received(:new).with(
        conversation_engine:, kb_source:, classifier:, loader_drafter:, review_repo:, logger: anything, store: true
      )
    end

    it "records documents and sections in the --collection through one registry shared by both pipelines (fact 8)" do
      registries = []
      allow(SFL::Core::Pipeline).to receive(:new).and_wrap_original do |original, **kwargs|
        registries << kwargs[:section_registry]
        original.call(**kwargs)
      end
      described_class.run_ingest("./inbox", options)

      expect(SFL::Store::PgSectionRegistry).to have_received(:new)
        .with(boot_result.db, collection: "inbox", logger: anything).once
      expect(registries.size).to eq(2)
      expect(registries.uniq.size).to eq(1)
    end

    it "writes the run to the runs table under SFL_RUN_ID and finishes it (fact 21)" do
      described_class.run_ingest("./inbox", options)

      expect(run_log.rows["run-7"]).to include(kind: "ingest", collection: "inbox", status: "finished",
        pid: Process.pid)
    end

    it "marks the run failed when the orchestrator raises" do
      allow(orchestrator).to receive(:run).and_raise(SFL::Store::Error, "boom")

      expect { described_class.run_ingest("./inbox", options) }.to raise_error(SFL::Store::Error)
      expect(run_log.rows["run-7"][:status]).to eq("failed")
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
