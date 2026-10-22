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
    it "gives dir, ./dir and the absolute path the same document_key and section ids" do
      write("notes.md", "# Title\n\nThis paragraph is long enough to pass the loader's minimum section length.\n")
      refs = []
      allow(kb_source).to receive(:analyze) { |ref, **| refs << ref }
      relative = Pathname(tmpdir).relative_path_from(Dir.pwd).to_s

      [relative, "./#{relative}", tmpdir].each { |spelling| orchestrator.run(spelling) }

      units = refs.map { |ref| SFL::Core::Loaders::MarkdownSource.new(ref).units }
      expect(refs.map(&:path_hint).uniq).to eq([File.join(tmpdir, "notes.md")])
      expect(units.map { |u| u.map(&:document_key) }.uniq.size).to eq(1)
      expect(units.map { |u| u.map(&:section_id) }.uniq.size).to eq(1)
      expect(units.first).not_to be_empty
    end

    it "dispatches a deterministically-matched conversation file without calling the classifier" do
      write("chat.jsonl", %({"name":"a","mes":"hi","send_date":"2026-01-01"}\n))
      allow(classifier).to receive(:classify)

      summary = orchestrator.run(tmpdir)

      expect(conversation_engine).to have_received(:analyze)
      expect(classifier).not_to have_received(:classify)
      expect(summary[:dispatched]).to eq(1)
    end

    it "forwards store: to every dispatch so a stored ingest persists its documents" do
      write("chat.jsonl", %({"name":"a","mes":"hi","send_date":"2026-01-01"}\n))
      write("notes.md", "# Title")
      stored = described_class.new(conversation_engine:, kb_source:, classifier:, loader_drafter:, review_repo:,
        store: true)

      stored.run(tmpdir)

      expect(conversation_engine).to have_received(:analyze).with(anything, label: "chat", store: true)
      expect(kb_source).to have_received(:analyze).with(anything, store: true)
    end

    it "dispatches a deterministically-matched knowledge_base file to kb_source" do
      write("notes.md", "# Title")

      orchestrator.run(tmpdir)

      expect(kb_source).to have_received(:analyze)
    end

    it "dispatches a transcription_*.txt file to a TranscriptionSource without calling the classifier" do
      write("transcription_2025-04-25_19-45-27.txt", "one line\n\nanother line\n")
      allow(classifier).to receive(:classify)

      summary = orchestrator.run(tmpdir)

      expect(conversation_engine).to have_received(:analyze).with(
        instance_of(SFL::Core::Loaders::TranscriptionSource),
        label: "transcription_2025-04-25_19-45-27", store: false
      ).once
      expect(conversation_engine).to have_received(:analyze).once
      expect(classifier).not_to have_received(:classify)
      expect(summary[:dispatched]).to eq(1)
    end

    it "dispatches an image-*.meta.yaml file to an ImageMetaSource without calling the classifier" do
      write("image-1381-1026.png.meta.yaml", "description: A diagram\n")
      allow(classifier).to receive(:classify)

      summary = orchestrator.run(tmpdir)

      expect(conversation_engine).to have_received(:analyze).with(
        instance_of(SFL::Core::Loaders::ImageMetaSource),
        label: "image-1381-1026.png.meta", store: false
      )
      expect(classifier).not_to have_received(:classify)
      expect(summary[:dispatched]).to eq(1)
    end

    it "still routes an ordinary notes.txt through the classifier, not the transcription loader" do
      path = write("notes.txt", "just a note\n")
      classifier_results[File.read(path)] = SFL::Core::Types::ClassificationResult.new(
        format: "unknown", mode: nil, confidence: 0.1, reasoning: "no loader recognizes this shape"
      )
      allow(loader_drafter).to receive(:draft).and_return(
        loader_path: "lib/sfl/core/loaders/x_source.rb", doc_path: "docs/ingest-review/x_source.md"
      )

      orchestrator.run(tmpdir)

      expect(conversation_engine).not_to have_received(:analyze)
      expect(loader_drafter).to have_received(:draft)
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
      expect(row).to include(
        status: "low_confidence_mode",
        path:,
        format: "markdown",
        mode: "conversation",
        confidence: 0.4,
        reasoning: "Has speaker-labeled lines but also prose paragraphs"
      )
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
      expect(row).to include(
        status: "loader_drafted", path:, format: "unknown", confidence: 0.1,
        reasoning: "no loader recognizes this shape",
        loader_path: "lib/sfl/core/loaders/x_source.rb", doc_path: "docs/ingest-review/x_source.md"
      )
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

    it "logs the run summary through the injected logger" do
      logger = instance_double(SFL::Core::Ports::Null::Logger)
      allow(logger).to receive(:info)
      logged = described_class.new(
        conversation_engine:, kb_source:, classifier:, loader_drafter:, review_repo:, logger:
      )

      summary = logged.run(tmpdir)

      expect(logger).to have_received(:info)
        .with("ingest run complete", dispatched: 0, review_entries: 0, drafted: 0)
      expect(summary).to include(dispatched: 0, review_entries: 0, drafted: 0)
    end

    it "records a section id conflict against its file and continues with the next file" do
      clash = write("a.jsonl", %({"name":"a","mes":"hi","send_date":"2026-01-01"}\n))
      write("b.jsonl", %({"name":"a","mes":"hi","send_date":"2026-01-01"}\n))
      error = SFL::Core::Ports::SectionRegistry::ConflictError.new("section a#turn-1 belongs to /x/a.jsonl, not #{clash}")
      allow(conversation_engine).to receive(:analyze).with(anything, label: "a", store: false).and_raise(error)

      summary = orchestrator.run(tmpdir)

      expect(summary).to include(dispatched: 1, review_entries: 1)
      row = SFL::Store::StoreTestDb.db[:ingest_review_entries].where(path: clash).first
      expect(row).to include(status: "draft_failed", reasoning: "Dispatch failed: #{error.message}")
    end
  end

  describe "classifier verdict dispatch" do
    def spy_logger
      logger = instance_double(SFL::Core::Ports::Null::Logger)
      allow(logger).to receive(:info)
      allow(logger).to receive(:error)
      allow(logger).to receive(:warn)
      logger
    end

    it "dispatches a documentation-mode verdict to a DocumentationSource through the conversation engine" do
      path = write("manual.unknownext", "manual prose")
      classifier_results[File.read(path)] = SFL::Core::Types::ClassificationResult.new(
        format: "manual", mode: "documentation", confidence: 0.9, reasoning: "reads like a manual"
      )

      doc_source = instance_double(SFL::Analysis::DocumentationSource)
      allow(SFL::Analysis::DocumentationSource).to receive(:new).and_return(doc_source)

      summary = orchestrator.run(tmpdir)

      expect(SFL::Analysis::DocumentationSource).to have_received(:new)
        .with(single_ref: kind_of(SFL::Core::Refs::FileRef))
      expect(conversation_engine).to have_received(:analyze).with(doc_source, label: "manual", store: false)
      expect(summary).to include(dispatched: 1, review_entries: 0, drafted: 0)
    end

    it "builds the ConversationSource with the deterministic match's source_type" do
      write("export.json", %([{"mapping": {"a": {"message": null}}}]))
      convo_source = instance_double(SFL::Analysis::ConversationSource)
      allow(SFL::Analysis::ConversationSource).to receive(:new).and_return(convo_source)

      orchestrator.run(tmpdir)

      expect(SFL::Analysis::ConversationSource).to have_received(:new)
        .with(kind_of(SFL::Core::Refs::FileRef), source_type: "chat_chatgpt")
      expect(conversation_engine).to have_received(:analyze).with(convo_source, label: "export", store: false)
    end

    it "falls back to the verdict's format when a classifier verdict has no source_type" do
      path = write("rows.ndjson", %({"role":"user","content":"hi"}\n))
      classifier_results[File.read(path)] = SFL::Core::Types::ClassificationResult.new(
        format: "generic_jsonl_chat", mode: "conversation", confidence: 0.9, reasoning: "looks like chat rows"
      )
      convo_source = instance_double(SFL::Analysis::ConversationSource)
      allow(SFL::Analysis::ConversationSource).to receive(:new).and_return(convo_source)
      allow(classifier).to receive(:classify).and_call_original

      orchestrator.run(tmpdir)

      expect(SFL::Analysis::ConversationSource).to have_received(:new)
        .with(kind_of(SFL::Core::Refs::FileRef), source_type: "generic_jsonl_chat")
      expect(classifier).to have_received(:classify).with(File.read(path), path)
    end

    it "dispatches a classifier verdict exactly at the confidence threshold" do
      path = write("edge.unknownext", "borderline shape")
      classifier_results[File.read(path)] = SFL::Core::Types::ClassificationResult.new(
        format: "generic_chat", mode: "conversation", confidence: 0.6, reasoning: "right at the boundary"
      )

      summary = orchestrator.run(tmpdir)

      expect(conversation_engine).to have_received(:analyze)
      expect(summary).to include(dispatched: 1, review_entries: 0, drafted: 0)
    end

    it "does not dispatch a high-confidence verdict whose mode is nil" do
      path = write("nomode.unknownext", "modeless shape")
      classifier_results[File.read(path)] = SFL::Core::Types::ClassificationResult.new(
        format: "generic_chat", mode: nil, confidence: 0.9, reasoning: "a shape without a mode"
      )

      summary = orchestrator.run(tmpdir)

      expect(conversation_engine).not_to have_received(:analyze)
      expect(summary).to include(dispatched: 0, review_entries: 1)
      row = review_repo.find(SFL::Store::StoreTestDb.db[:ingest_review_entries].first[:id])
      expect(row).to include(
        status: "low_confidence_mode", path:, format: "generic_chat", mode: nil,
        confidence: 0.9, reasoning: "a shape without a mode"
      )
    end

    it "hands the drafter the sample classify already read, not a fresh re-read" do
      path = write("novel.unknownext", "will be read twice")
      classifier_results.default = SFL::Core::Types::ClassificationResult.new(
        format: "unknown", mode: nil, confidence: 0.1, reasoning: "no loader recognizes this shape"
      )
      allow(classifier).to receive(:classify).and_return(classifier_results.default)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(path, described_class::SAMPLE_BYTES).and_return("first read", "second read")
      allow(loader_drafter).to receive(:draft).and_return(
        loader_path: "lib/sfl/core/loaders/x_source.rb", doc_path: "docs/ingest-review/x_source.md"
      )

      orchestrator.run(tmpdir)

      expect(loader_drafter).to have_received(:draft).with("first read", path)
    end

    it "judges the format by value equality, not object identity" do
      path = write("odd.unknownext", "novel shape")
      classifier_results[File.read(path)] = SFL::Core::Types::ClassificationResult.new(
        format: +"unknown", mode: nil, confidence: 0.1, reasoning: "no loader recognizes this shape"
      )
      allow(loader_drafter).to receive(:draft).and_return(
        loader_path: "lib/sfl/core/loaders/x_source.rb", doc_path: "docs/ingest-review/x_source.md"
      )

      summary = orchestrator.run(tmpdir)

      expect(loader_drafter).to have_received(:draft)
      expect(summary).to include(drafted: 1, review_entries: 0)
    end

    it "logs each per-file failure and the run's counts through the injected logger" do
      logger = spy_logger
      logged = described_class.new(
        conversation_engine:, kb_source:, classifier:, loader_drafter:, review_repo:, logger:
      )
      write("a.md", "doc a")
      write("b.md", "doc b")
      raised = false
      allow(kb_source).to receive(:analyze) do
        next kb_result if raised

        raised = true
        raise SFL::Analysis::Error, "boom"
      end

      summary = logged.run(tmpdir)

      expect(logger).to have_received(:error)
        .with("ingest failed", file: kind_of(String), error_class: eq(SFL::Analysis::Error), error_message: "boom")
      expect(logger).to have_received(:info)
        .with("ingest run complete", dispatched: 1, review_entries: 1, drafted: 0)
      expect(summary).to include(dispatched: 1, review_entries: 1)
    end

    it "warns with the file and message when LoaderDrafter raises" do
      logger = spy_logger
      path = write("weird.unknownext", "novel shape")
      classifier_results.default = SFL::Core::Types::ClassificationResult.new(
        format: "unknown", mode: nil, confidence: 0.1, reasoning: "no loader recognizes this shape"
      )
      allow(classifier).to receive(:classify).and_return(classifier_results.default)
      allow(loader_drafter).to receive(:draft).and_raise(SFL::Ingest::LoaderDrafter::Error, "rate limited")
      logged = described_class.new(
        conversation_engine:, kb_source:, classifier:, loader_drafter:, review_repo:, logger:
      )

      summary = logged.run(tmpdir)

      expect(logger).to have_received(:warn).with("loader draft failed", file: path, error_message: "rate limited")
      expect(summary).to include(drafted: 0, review_entries: 1)
      row = SFL::Store::StoreTestDb.db[:ingest_review_entries].where(path:).first
      expect(review_repo.find(row[:id])).to include(status: "draft_failed", path:, reasoning: "Draft failed: rate limited")
    end
  end

  describe "loaders registry" do
    it "defaults loaders: to a Core::Registry populated via Catalog.register_into" do
      loaders = orchestrator.__send__(:loaders)

      expect(loaders).to be_a(SFL::Core::Registry)
      expect(loaders.names).to include(:transcription, :image_meta, :subtitle, :markdown)
    end

    it "keeps an explicitly injected loaders: registry instead of building the default one" do
      loaders = instance_double(SFL::Core::Registry)
      injected = described_class.new(
        conversation_engine:, kb_source:, classifier:, loader_drafter:, review_repo:, loaders:
      )

      expect(injected.__send__(:loaders)).to be(loaders)
    end

    it "resolves a registered source_type's factory through the injected registry" do
      write("transcription_2025-04-25_19-45-27.txt", "one line\n")
      loader = instance_double(SFL::Core::Loaders::TranscriptionSource)
      loaders = instance_double(SFL::Core::Registry)
      allow(loaders).to receive(:resolve!).with(:transcription, ref: kind_of(SFL::Core::Refs::FileRef)).and_return(loader)
      injected = described_class.new(
        conversation_engine:, kb_source:, classifier:, loader_drafter:, review_repo:, loaders:
      )

      injected.run(tmpdir)

      expect(loaders).to have_received(:resolve!).with(:transcription, ref: kind_of(SFL::Core::Refs::FileRef))
      expect(conversation_engine).to have_received(:analyze)
        .with(loader, label: "transcription_2025-04-25_19-45-27", store: false)
    end

    it "resolves vault_image_meta through the injected registry too" do
      write("image-1381-1026.png.meta.yaml", "description: A diagram\n")
      loader = instance_double(SFL::Core::Loaders::ImageMetaSource)
      loaders = instance_double(SFL::Core::Registry)
      allow(loaders).to receive(:resolve!).with(:image_meta, ref: kind_of(SFL::Core::Refs::FileRef)).and_return(loader)
      injected = described_class.new(
        conversation_engine:, kb_source:, classifier:, loader_drafter:, review_repo:, loaders:
      )

      injected.run(tmpdir)

      expect(loaders).to have_received(:resolve!).with(:image_meta, ref: kind_of(SFL::Core::Refs::FileRef))
      expect(conversation_engine).to have_received(:analyze)
        .with(loader, label: "image-1381-1026.png.meta", store: false)
    end
  end
end
