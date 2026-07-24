# frozen_string_literal: true

require "spec_helper"
require "ruby_llm"

RSpec.describe SFL::CLI do
  let(:chat_factory) { instance_double(SFL::LLM::ChatFactory) }
  let(:boot_result) do
    SFL::Boot::Result.new(
      db: instance_double(Sequel::Database), llm_config: instance_double(SFL::LLM::Config), chat_factory:,
      embedder: instance_double(SFL::LLM::Embedder), pass1_command: nil, spacy_model: "en_core_web_sm"
    )
  end
  let(:kb_source) { instance_double(SFL::Analysis::KnowledgeBaseSource) }
  let(:result) do
    instance_double(
      SFL::Core::Types::KnowledgeBaseReport,
      metadata: { artifact_count: 2, file_count: 1 }, staleness_flags: []
    )
  end

  before do
    allow(SFL::Core::PassOne::SpacySidecarParser).to receive(:new)
      .and_return(instance_double(SFL::Core::PassOne::SpacySidecarParser))
    allow(SFL::Boot).to receive(:call).and_return(boot_result)
    allow(SFL::LLM::EngineBuilder).to receive(:call).and_return(instance_double(SFL::LLM::Engine))
    allow(SFL::Analysis::KnowledgeBaseSource).to receive(:new).and_return(kb_source)
    allow(kb_source).to receive(:analyze).and_return(result)
    allow(SFL::Formatters::KBReportWriter).to receive(:write).and_return({})
    allow($stdout).to receive(:puts)
  end

  describe ".run_knowledge_base" do
    let(:options) do
      {
        output_dir: "./out",
        store: false,
        images: false,
        vision_model: nil,
        resume: false,
        annotated: false,
        disable_tracing: false,
      }
    end

    it "always boots with require_llm: true (no --pass1-only option exists for this subcommand)" do
      described_class.run_knowledge_base("./vault", options)

      expect(SFL::Boot).to have_received(:call).with(require_llm: true, require_tracing: true)
    end

    it "builds KnowledgeBaseSource with chat: nil when --images is not set" do
      described_class.run_knowledge_base("./vault", options)

      expect(SFL::Analysis::KnowledgeBaseSource).to have_received(:new)
        .with(hash_including(analyze_images: false, chat: nil))
    end

    it "resolves chat: from chat_factory.for(:context_synthesis) when --images is set" do
      chat = instance_double(RubyLLM::Chat)
      allow(chat_factory).to receive(:for).with(:context_synthesis).and_return(chat)

      described_class.run_knowledge_base("./vault", options.merge(images: true))

      expect(SFL::Analysis::KnowledgeBaseSource).to have_received(:new)
        .with(hash_including(analyze_images: true, chat:))
    end

    it "forwards store:/resume: to KnowledgeBaseSource#analyze" do
      described_class.run_knowledge_base("./vault", options.merge(store: true, resume: true))

      expect(kb_source).to have_received(:analyze).with("./vault", store: true, resume: true)
    end

    it "writes the CSV/JSON/Markdown trio and skips the annotated writer when --annotated is not set" do
      allow(SFL::Formatters::KBAnnotatedDocWriter).to receive(:write)

      described_class.run_knowledge_base("./vault", options)

      expect(SFL::Formatters::KBReportWriter).to have_received(:write).with(result, "./out")
      expect(SFL::Formatters::KBAnnotatedDocWriter).not_to have_received(:write)
    end

    it "also writes annotated docs when --annotated is set" do
      allow(SFL::Formatters::KBAnnotatedDocWriter).to receive(:write).and_return(["./out/annotated/a.md"])

      described_class.run_knowledge_base("./vault", options.merge(annotated: true))

      expect(SFL::Formatters::KBAnnotatedDocWriter).to have_received(:write).with(result, "./out")
    end
  end
end
