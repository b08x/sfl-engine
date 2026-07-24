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
  let(:logger) { instance_double(SFL::Core::Ports::StandardLogger) }
  let(:instrumenter) { SFL::Core::Ports::Null::Instrumenter.new }
  let(:breaker) { SFL::Core::Ports::Null::Breaker.new }
  let(:parser_double) { instance_double(SFL::Core::PassOne::SpacySidecarParser) }
  let(:file_cache_double) { instance_double(SFL::Core::Ports::FileCache) }

  before do
    allow(SFL::Core::PassOne::SpacySidecarParser).to receive(:new).and_return(parser_double)
    allow(SFL::Core::Ports::FileCache).to receive(:new).and_return(file_cache_double)
  end

  describe ".build_pipeline" do
    it "wires SpacySidecarParser from boot_result's spacy_model/pass1_command/logger" do
      allow(SFL::LLM::EngineBuilder).to receive(:call)

      described_class.build_pipeline(boot_result, { pass1_only: false, store: false, resume: false },
        breaker:, instrumenter:, logger:)

      expect(SFL::Core::PassOne::SpacySidecarParser).to have_received(:new)
        .with(model: "en_core_web_sm", command: nil, logger:)
    end

    it "builds a real Pass 2 engine via EngineBuilder when pass1_only is false" do
      engine_double = instance_double(SFL::LLM::Engine)
      allow(SFL::LLM::EngineBuilder).to receive(:call).and_return(engine_double)

      pipeline = described_class.build_pipeline(boot_result, { pass1_only: false, store: false, resume: false },
        breaker:, instrumenter:, logger:)

      expect(SFL::LLM::EngineBuilder).to have_received(:call).with(
        config: boot_result.llm_config, chat_factory: boot_result.chat_factory, breaker:, instrumenter:, logger:
      )
      expect(pipeline.__send__(:pass_two)).to eq(engine_double)
    end

    it "injects Ports::Null::Annotator as pass_two when pass1_only is true, never building a real Engine" do
      allow(SFL::LLM::EngineBuilder).to receive(:call)

      pipeline = described_class.build_pipeline(boot_result, { pass1_only: true, store: false, resume: false },
        breaker:, instrumenter:, logger:)

      expect(SFL::LLM::EngineBuilder).not_to have_received(:call)
      expect(pipeline.__send__(:pass_two)).to be_a(SFL::Core::Ports::Null::Annotator)
    end

    it "injects boot_result's real embedder and a PgEmbeddingStore only when store: true" do
      allow(SFL::LLM::EngineBuilder).to receive(:call)

      stored = described_class.build_pipeline(boot_result, { pass1_only: false, store: true, resume: false },
        breaker:, instrumenter:, logger:)
      expect(stored.__send__(:embedder)).to eq(boot_result.embedder)
      expect(stored.__send__(:embedding_store)).to be_a(SFL::Store::PgEmbeddingStore)

      unstored = described_class.build_pipeline(boot_result, { pass1_only: false, store: false, resume: false },
        breaker:, instrumenter:, logger:)
      expect(unstored.__send__(:embedder)).to be_a(SFL::Core::Ports::Null::Embedder)
      expect(unstored.__send__(:embedding_store)).to be_a(SFL::Core::Ports::Null::EmbeddingStore)
    end

    it "injects a FileCache only when resume: true" do
      allow(SFL::LLM::EngineBuilder).to receive(:call)

      resumed = described_class.build_pipeline(boot_result, { pass1_only: false, store: false, resume: true },
        breaker:, instrumenter:, logger:)
      expect(resumed.__send__(:cache)).to eq(file_cache_double)
      expect(SFL::Core::Ports::FileCache).to have_received(:new)

      fresh = described_class.build_pipeline(boot_result, { pass1_only: false, store: false, resume: false },
        breaker:, instrumenter:, logger:)
      expect(fresh.__send__(:cache)).to be_a(SFL::Core::Ports::Null::Cache)
    end

    it "always injects a real PgClauseStore regardless of store:" do
      allow(SFL::LLM::EngineBuilder).to receive(:call)

      pipeline = described_class.build_pipeline(boot_result, { pass1_only: false, store: false, resume: false },
        breaker:, instrumenter:, logger:)

      expect(pipeline.__send__(:clause_store)).to be_a(SFL::Store::PgClauseStore)
    end
  end
end
