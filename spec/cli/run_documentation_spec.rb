# frozen_string_literal: true

require "spec_helper"
require "ruby_llm"

RSpec.describe SFL::CLI do
  let(:boot_result) do
    SFL::Boot::Result.new(
      db: instance_double(Sequel::Database), llm_config: instance_double(SFL::LLM::Config),
      chat_factory: instance_double(SFL::LLM::ChatFactory), embedder: instance_double(SFL::LLM::Embedder),
      pass1_command: nil, spacy_model: "en_core_web_sm"
    )
  end
  let(:engine) { instance_double(SFL::Analysis::Engine) }
  let(:source) { instance_double(SFL::Analysis::DocumentationSource) }
  let(:result) { instance_double(SFL::Core::Types::AnalysisResult, metadata: { interrupted: false }, turns: []) }

  before do
    allow(SFL::Core::PassOne::SpacySidecarParser).to receive(:new)
      .and_return(instance_double(SFL::Core::PassOne::SpacySidecarParser))
    allow(SFL::Boot).to receive(:call).and_return(boot_result)
    allow(SFL::LLM::EngineBuilder).to receive(:call).and_return(instance_double(SFL::LLM::Engine))
    allow(SFL::Analysis::Engine).to receive(:new).and_return(engine)
    allow(SFL::Analysis::DocumentationSource).to receive(:new).and_return(source)
    allow(engine).to receive(:analyze).and_return(result)
    allow(SFL::Formatters::ReportWriter).to receive(:write).and_return({})
    allow($stdout).to receive(:puts)
  end

  describe ".run_documentation" do
    let(:options) do
      {
        output_dir: "./out",
        pass1_only: true,
        resume: false,
        store: false,
        narrative: false,
        topics: nil,
        disable_tracing: true,
      }
    end

    it "drives a single DocumentationSource over the whole input (no per-file batching, unlike conversation)" do
      described_class.run_documentation("./docs", options)

      expect(SFL::Analysis::DocumentationSource).to have_received(:new).with("./docs")
      expect(engine).to have_received(:analyze).with(
        source, label: "docs", store: false, resume: false, topics: nil, pass_one_only: true
      )
      expect(SFL::Formatters::ReportWriter).to have_received(:write).with(result, "./out")
    end

    it "boots with require_llm: false for --pass1-only" do
      described_class.run_documentation("./docs", options)

      expect(SFL::Boot).to have_received(:call).with(require_llm: false, require_tracing: false)
    end
  end
end
