# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe SFL::Ingest::Orchestrator do
  subject(:orchestrator) do
    described_class.new(
      conversation_engine:, kb_source:, classifier:, loader_drafter:, review_repo:
    )
  end

  let(:conversation_engine) { instance_double(SFL::Analysis::Engine, analyze: analysis_result) }
  let(:kb_source) { instance_double(SFL::Analysis::KnowledgeBaseSource, analyze: kb_result) }
  let(:analysis_result) { instance_double(SFL::Core::Types::AnalysisResult, metadata: {}) }
  let(:kb_result) { instance_double(SFL::Core::Types::KnowledgeBaseReport) }
  let(:classifier) { SFL::Core::Ports::Fake::Classifier.new(results: classifier_results) }
  let(:classifier_results) { {} }
  let(:loader_drafter) { instance_double(SFL::Ingest::LoaderDrafter) }
  let(:review_repo) { SFL::Store::PgIngestReviewRepository.new(SFL::Store::StoreTestDb.db) }
  let(:tmpdir) { Dir.mktmpdir }

  before { SFL::Store::StoreTestDb.clean! }

  after { FileUtils.remove_entry(tmpdir) }

  def write(name, content)
    path = File.join(tmpdir, name)
    File.write(path, content)
    path
  end

  describe "#run" do
    it "dispatches a deterministically-matched conversation file without calling the classifier" do
      write("chat.jsonl", %({"name":"a","mes":"hi","send_date":"2026-01-01"}\n))
      allow(classifier).to receive(:classify)

      summary = orchestrator.run(tmpdir)

      expect(conversation_engine).to have_received(:analyze)
      expect(classifier).not_to have_received(:classify)
      expect(summary[:dispatched]).to eq(1)
    end

    it "dispatches a deterministically-matched knowledge_base file to kb_source" do
      write("notes.md", "# Title")

      orchestrator.run(tmpdir)

      expect(kb_source).to have_received(:analyze)
    end

    it "dispatches via the classifier when a high-confidence verdict is returned for an " \
      "unrecognized extension" do
      path = write("data.ndjson", %({"role":"user","content":"hi"}\n))
      classifier_results[File.read(path)] = SFL::Core::Types::ClassificationResult.new(
        format: "generic_jsonl_chat", mode: "conversation", confidence: 0.9, reasoning: "looks like chat rows"
      )

      summary = orchestrator.run(tmpdir)

      expect(conversation_engine).to have_received(:analyze)
      expect(summary[:dispatched]).to eq(1)
    end

    it "writes a low_confidence_mode review entry, and does not dispatch, when the format " \
      "is known but the mode is ambiguous" do
      path = write("ambiguous.md", "some pasted chat maybe")
      # .md is a deterministic KB match by extension — force the low-confidence path by
      # stubbing the classifier not to be consulted; instead simulate the ambiguous case via
      # a KB-extension file the deterministic rules would normally match confidently. To
      # exercise the *classifier's* low-confidence branch specifically, use an unrecognized
      # extension whose classifier verdict has a known format but nil/low-confidence mode:
      File.delete(path)
      path = write("ambiguous.unknownext", "some pasted chat maybe")
      classifier_results[File.read(path)] = SFL::Core::Types::ClassificationResult.new(
        format: "markdown", mode: "conversation", confidence: 0.4,
        reasoning: "Has speaker-labeled lines but also prose paragraphs"
      )

      summary = orchestrator.run(tmpdir)

      expect(conversation_engine).not_to have_received(:analyze)
      expect(kb_source).not_to have_received(:analyze)
      expect(summary[:review_entries]).to eq(1)
      row = review_repo.find(SFL::Store::StoreTestDb.db[:ingest_review_entries].first[:id])
      expect(row[:status]).to eq("low_confidence_mode")
    end

    it "drafts a loader and writes a loader_drafted review entry when format itself is unknown" do
      path = write("weird.unknownext", "totally novel shape")
      classifier_results[File.read(path)] = SFL::Core::Types::ClassificationResult.new(
        format: "unknown", mode: nil, confidence: 0.1, reasoning: "no loader recognizes this shape"
      )
      allow(loader_drafter).to receive(:draft).and_return(
        loader_path: "lib/sfl/core/loaders/x_source.rb", doc_path: "docs/ingest-review/x_source.md"
      )

      summary = orchestrator.run(tmpdir)

      expect(loader_drafter).to have_received(:draft)
      expect(conversation_engine).not_to have_received(:analyze)
      expect(summary[:drafted]).to eq(1)
      row = review_repo.find(SFL::Store::StoreTestDb.db[:ingest_review_entries].first[:id])
      expect(row[:status]).to eq("loader_drafted")
      expect(row[:loader_path]).to eq("lib/sfl/core/loaders/x_source.rb")
    end

    it "writes a draft_failed review entry, and continues, when LoaderDrafter raises" do
      write("weird.unknownext1", "novel shape one")
      write("weird.unknownext2", "novel shape two")
      classifier_results.default = SFL::Core::Types::ClassificationResult.new(
        format: "unknown", mode: nil, confidence: 0.1, reasoning: "no loader recognizes this shape"
      )
      allow(classifier).to receive(:classify).and_return(classifier_results.default)
      allow(loader_drafter).to receive(:draft).and_raise(SFL::Ingest::LoaderDrafter::Error, "rate limited")

      summary = orchestrator.run(tmpdir)

      expect(summary[:drafted]).to eq(0)
      expect(summary[:review_entries]).to eq(2)
      rows = SFL::Store::StoreTestDb.db[:ingest_review_entries].all
      expect(rows.map { |r| r[:status] }).to all(eq("draft_failed"))
    end

    it "skips a path whose review entry is already resolved on a rerun" do
      path = write("weird.unknownext", "totally novel shape")
      review_repo.enqueue(path:, status: "resolved", reasoning: "handled by hand")
      SFL::Store::StoreTestDb.db[:ingest_review_entries].where(path:).update(resolved_at: Time.now)
      allow(classifier).to receive(:classify)

      summary = orchestrator.run(tmpdir)

      expect(classifier).not_to have_received(:classify)
      expect(summary[:dispatched]).to eq(0)
      expect(summary[:review_entries]).to eq(0)
      expect(summary[:drafted]).to eq(0)
    end

    it "continues processing remaining files when one file's dispatch raises (F11 " \
      "partial-failure isolation)" do
      write("a.md", "doc a")
      write("b.md", "doc b")
      raised = false
      allow(kb_source).to receive(:analyze) do
        next kb_result if raised

        raised = true
        raise SFL::Analysis::Error, "boom"
      end

      summary = orchestrator.run(tmpdir)

      expect(summary[:dispatched]).to eq(1)
      expect(kb_source).to have_received(:analyze).twice
    end

    it "writes a draft_failed review entry, and continues, when a file vanishes mid-walk " \
      "(SystemCallError from the initial sampling File.read is not swallowed by " \
      "Analysis::Error/Core::Loaders::Error/Store::Error alone)" do
      gone_path = write("gone.unknownext", "will disappear")
      write("still.unknownext", "still here")
      classifier_results.default = SFL::Core::Types::ClassificationResult.new(
        format: "unknown", mode: nil, confidence: 0.1, reasoning: "no loader recognizes this shape"
      )
      allow(loader_drafter).to receive(:draft).and_return(
        loader_path: "lib/sfl/core/loaders/x_source.rb", doc_path: "docs/ingest-review/x_source.md"
      )
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(gone_path, described_class::SAMPLE_BYTES).and_raise(Errno::ENOENT)

      summary = orchestrator.run(tmpdir)

      expect(summary[:review_entries]).to eq(1)
      row = SFL::Store::StoreTestDb.db[:ingest_review_entries].where(path: gone_path).first
      expect(review_repo.find(row[:id])[:status]).to eq("draft_failed")
    end
  end
end
