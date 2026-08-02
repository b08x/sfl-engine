# frozen_string_literal: true

require "spec_helper"
require "ruby_llm"
require "tmpdir"

RSpec.describe SFL::CLI do
  let(:boot_result) do
    SFL::Boot::Result.new(
      db: instance_double(Sequel::Database), llm_config: instance_double(SFL::LLM::Config),
      chat_factory: instance_double(SFL::LLM::ChatFactory), embedder: instance_double(SFL::LLM::Embedder),
      pass1_command: nil, spacy_model: "en_core_web_sm"
    )
  end
  let(:engine) { instance_double(SFL::Analysis::Engine) }
  let(:source) { instance_double(SFL::Analysis::ConversationSource) }
  let(:result) { instance_double(SFL::Core::Types::AnalysisResult, metadata: { interrupted: false }, turns: []) }

  before do
    allow(SFL::Core::PassOne::SpacySidecarParser).to receive(:new)
      .and_return(instance_double(SFL::Core::PassOne::SpacySidecarParser))
    allow(SFL::Boot).to receive(:call).and_return(boot_result)
    allow(SFL::LLM::EngineBuilder).to receive(:call).and_return(instance_double(SFL::LLM::Engine))
    allow(SFL::Analysis::Engine).to receive(:new).and_return(engine)
    allow(SFL::Analysis::ConversationSource).to receive(:new).and_return(source)
    allow(engine).to receive(:analyze).and_return(result)
    allow(SFL::Formatters::ReportWriter).to receive(:write).and_return({})
    allow($stdout).to receive(:puts)
    allow($stdout).to receive(:print)
  end

  describe ".run_conversation" do
    let(:base_options) do
      {
        output_dir: "./out",
        pass1_only: false,
        resume: true,
        store: true,
        narrative: false,
        topics: 3,
        disable_tracing: false,
      }
    end

    it "boots with require_llm/require_tracing derived from pass1_only/disable_tracing, and forwards options " \
      "to Engine#analyze" do
      described_class.run_conversation("convo.jsonl", base_options)

      expect(SFL::Boot).to have_received(:call).with(require_llm: true, require_tracing: true)
      expect(SFL::Analysis::ConversationSource).to have_received(:new).with("convo.jsonl", source_type: "chat_native")
      expect(engine).to have_received(:analyze).with(
        source, label: "convo", store: true, resume: true, topics: 3, pass_one_only: false
      )
      expect(SFL::Formatters::ReportWriter).to have_received(:write).with(result, "./out")
    end

    it "passes require_llm: false when pass1_only is set (skips API-key validation / ChatFactory cost)" do
      described_class.run_conversation("convo.jsonl", base_options.merge(pass1_only: true))

      expect(SFL::Boot).to have_received(:call).with(require_llm: false, require_tracing: true)
    end

    it "passes require_tracing: false when disable_tracing is set" do
      described_class.run_conversation("convo.jsonl", base_options.merge(disable_tracing: true))

      expect(SFL::Boot).to have_received(:call).with(require_llm: true, require_tracing: false)
    end

    it "raises UsageError when a directory input has no matching files" do
      Dir.mktmpdir do |dir|
        expect { described_class.run_conversation(dir, base_options) }
          .to raise_error(SFL::CLI::UsageError, /No \.jsonl/)
      end
    end

    it "writes a report into a per-file subdirectory when the directory has multiple matching files" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a.jsonl"), "")
        File.write(File.join(dir, "b.jsonl"), "")

        described_class.run_conversation(dir, base_options)

        expect(SFL::Formatters::ReportWriter).to have_received(:write).with(result, File.join("./out", "a"))
        expect(SFL::Formatters::ReportWriter).to have_received(:write).with(result, File.join("./out", "b"))
      end
    end

    it "accepts a raw ChatGPT/Claude export .json file directly, expanding it into per-conversation " \
      "JSONL under <output_dir>/_expanded instead of raising 'Unsupported conversation input format' " \
      "(live-verified gap, 2026-08-02 — a single-file .json argument used to skip format validation " \
      "entirely and fail deep inside ConversationSource#raw_turns)" do
      Dir.mktmpdir do |dir|
        output_dir = File.join(dir, "out")
        described_class.run_conversation("spec/fixtures/loaders/chatgpt_conversations.json",
          base_options.merge(output_dir:))

        expect(SFL::Analysis::ConversationSource).to have_received(:new)
          .with(a_string_matching(%r{_expanded/explaining-rrf}), source_type: "chat_chatgpt")
        expanded_path = Dir.glob(File.join(output_dir, "_expanded", "*.jsonl")).first
        expect(File.read(expanded_path)).to include("What is reciprocal rank fusion?")
      end
    end
  end
end
