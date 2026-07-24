# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe SFL::CLI do
  let(:chat_factory) { instance_double(SFL::LLM::ChatFactory) }
  let(:chat) { instance_double(RubyLLM::Chat) }
  let(:boot_result) do
    SFL::Boot::Result.new(
      db: instance_double(Sequel::Database), llm_config: instance_double(SFL::LLM::Config), chat_factory:,
      embedder: instance_double(SFL::LLM::Embedder), pass1_command: nil, spacy_model: "en_core_web_sm"
    )
  end
  let(:synthesizer) { instance_double(SFL::Retrieval::ContextSynthesizer) }

  before do
    allow(SFL::Boot).to receive(:call).and_return(boot_result)
    allow(chat_factory).to receive(:for).with(:context_synthesis).and_return(chat)
    allow(SFL::Store::PgHybridRetriever).to receive(:new).and_return(instance_double(SFL::Store::PgHybridRetriever))
    allow(SFL::Retrieval::ContextSynthesizer).to receive(:new).and_return(synthesizer)
    allow($stdout).to receive(:puts)
  end

  describe ".run_context" do
    let(:options) { { output_dir: nil, limit: 5, filters: { mood: "declarative" }, disable_tracing: false } }

    it "boots with require_llm: true and builds ContextSynthesizer from a PgHybridRetriever + context_synthesis chat" do
      empty_result = instance_double(SFL::Core::Types::SynthesisResult, retrieved_count: 0)
      allow(synthesizer).to receive(:synthesize).and_return(empty_result)

      described_class.run_context("does it work?", options)

      expect(SFL::Boot).to have_received(:call).with(require_llm: true, require_tracing: true)
      expect(SFL::Store::PgHybridRetriever).to have_received(:new).with(db: boot_result.db,
        embedder: boot_result.embedder)
      expect(SFL::Retrieval::ContextSynthesizer).to have_received(:new)
        .with(hash_including(chat:))
      expect(synthesizer).to have_received(:synthesize).with("does it work?", filters: { mood: "declarative" },
        limit: 5)
    end

    it "prints an ingest hint and does not write a file when nothing was retrieved" do
      empty_result = instance_double(SFL::Core::Types::SynthesisResult, retrieved_count: 0)
      allow(synthesizer).to receive(:synthesize).and_return(empty_result)

      described_class.run_context("does it work?", options)

      expect($stdout).to have_received(:puts).with("No stored clauses matched. Ingest documents first:")
    end

    it "writes context_synthesis.json only when --output-dir is given" do
      hit_result = instance_double(
        SFL::Core::Types::SynthesisResult, retrieved_count: 1, answer: "yes", confidence: 0.9,
        cited_clause_ids: ["c-1"], clauses: [{ clause_id: "c-1", text: "It works.", document_id: "doc-1" }],
        to_h: { query: "does it work?", answer: "yes" }
      )
      allow(synthesizer).to receive(:synthesize).and_return(hit_result)

      Dir.mktmpdir do |dir|
        described_class.run_context("does it work?", options.merge(output_dir: File.join(dir, "out")))

        path = File.join(dir, "out", "context_synthesis.json")
        expect(File.exist?(path)).to be(true)
        expect(JSON.parse(File.read(path))).to eq("query" => "does it work?", "answer" => "yes")
      end
    end
  end
end
