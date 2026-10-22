# frozen_string_literal: true

require "spec_helper"
require "dspy"

RSpec.describe SFL::CLI do
  let(:boot_result) do
    SFL::Boot::Result.new(
      db: instance_double(Sequel::Database), llm_config: instance_double(SFL::LLM::Config),
      lm_factory: instance_double(SFL::LLM::LMFactory), embedder: instance_double(SFL::LLM::Embedder),
      pass1_command: nil, spacy_model: "en_core_web_sm"
    )
  end
  let(:kb_source) { instance_double(SFL::Analysis::KnowledgeBaseSource) }
  let(:refs) { [instance_double(SFL::Core::Refs::FileRef)] }
  let(:result) do
    instance_double(SFL::Core::Types::KnowledgeBaseReport, metadata: { artifact_count: 4, file_count: 2 },
      staleness_flags: [{}])
  end
  let(:options) do
    { output_dir: "./out", store: false, images: false, resume: false, annotated: false, disable_tracing: true }
  end

  before do
    allow(SFL::Core::PassOne::SpacySidecarParser).to receive(:new)
      .and_return(instance_double(SFL::Core::PassOne::SpacySidecarParser))
    allow(SFL::Boot).to receive(:call).and_return(boot_result)
    allow(SFL::LLM::EngineBuilder).to receive(:call).and_return(instance_double(SFL::LLM::Engine))
    allow(SFL::Analysis::KnowledgeBaseSource).to receive(:new).and_return(kb_source)
    allow(kb_source).to receive(:analyze).and_return(result)
    allow(described_class).to receive_messages(corpus_refs: refs, terminal?: false)
    allow(SFL::Formatters::KBReportWriter).to receive(:write).and_return({ json: "./out/kb.json" })
    allow(SFL::Formatters::KBAnnotatedDocWriter).to receive(:write).and_return(["./out/annotated/a.md"])
    allow($stdout).to receive(:puts)
  end

  describe ".run_knowledge_base" do
    it "boots with require_llm: true and honors --disable-tracing" do
      described_class.run_knowledge_base("./kb", options)

      expect(SFL::Boot).to have_received(:call).with(require_llm: true, require_tracing: false)
    end

    it "analyzes the corpus refs and writes the report" do
      described_class.run_knowledge_base("./kb", options)

      expect(kb_source).to have_received(:analyze).with(refs, store: false, resume: false)
      expect(SFL::Formatters::KBReportWriter).to have_received(:write).with(result, "./out")
      expect(SFL::Formatters::KBAnnotatedDocWriter).not_to have_received(:write)
      expect($stdout).to have_received(:puts).with("  JSON: ./out/kb.json")
      expect($stdout).to have_received(:puts).with("\nArtifacts: 4 | Stale: 1 | Files: 2")
    end

    it "writes the annotated documents with --annotated" do
      described_class.run_knowledge_base("./kb", options.merge(annotated: true))

      expect(SFL::Formatters::KBAnnotatedDocWriter).to have_received(:write).with(result, "./out")
      expect($stdout).to have_received(:puts).with("  ANNOTATED: 1 file(s) in ./out/annotated/")
    end
  end
end
