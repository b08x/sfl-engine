# frozen_string_literal: true

require "spec_helper"
require "dry/monads"

RSpec.describe SFL::Analysis::KnowledgeBaseSource do
  include Dry::Monads[:result]

  let(:pipeline) { instance_double(SFL::Core::Pipeline) }
  let(:sample_path) { "spec/fixtures/inputs/sample.md" }
  let(:sample_ref) { SFL::Core::Refs::FileRefBuilder.call(sample_path) }

  def clauses_for(count, id_prefix:)
    Array.new(count) { |i| build_annotated_clause(id: "#{id_prefix}#{i}", annotation_source: "llm", modality: 0.8) }
  end

  describe "#initialize" do
    it "raises a clear ArgumentError when analyze_images: true and chat: is nil" do
      expect { described_class.new(pipeline:, analyze_images: true, chat: nil) }
        .to raise_error(ArgumentError, /chat/)
    end

    it "does not raise when analyze_images: true and a chat: collaborator is provided" do
      chat = double("chat") # rubocop:disable RSpec/VerifiedDoubles -- ImageSource's chat is a duck (#ask)

      expect { described_class.new(pipeline:, analyze_images: true, chat:) }.not_to raise_error
    end

    it "does not raise when analyze_images is left at its false default with no chat:" do
      expect { described_class.new(pipeline:) }.not_to raise_error
    end
  end

  describe "#analyze" do
    before do
      allow(pipeline).to receive(:compile).and_return(Success(clauses_for(3, id_prefix: "c")))
    end

    it "passes each loader unit to Pipeline#compile" do
      described_class.new(pipeline:).analyze(sample_ref)

      expect(pipeline).to have_received(:compile)
        .with(anything, hash_including(unit: an_instance_of(SFL::Core::Types::Unit))).exactly(3).times
    end

    it "assembles a Core::Types::KnowledgeBaseReport from a markdown fixture's sections" do
      source = described_class.new(pipeline:)

      report = source.analyze(sample_ref)

      expect(report).to be_a(SFL::Core::Types::KnowledgeBaseReport)
      expect(report.artifacts.size).to eq(3) # Introduction / Usage / Advanced Topics
      expect(report.artifacts.map(&:section_path)).to eq(["Introduction", "Usage", "Advanced Topics"])
    end

    it "assigns sequential artifact_ids starting at 1" do
      source = described_class.new(pipeline:)

      report = source.analyze(sample_ref)

      expect(report.artifacts.map(&:artifact_id)).to eq([1, 2, 3])
    end

    it "backfills migration_action/migration_reason from the migration_manifest onto each artifact" do
      source = described_class.new(pipeline:)

      report = source.analyze(sample_ref)

      manifest_by_id = report.migration_manifest.to_h { |m| [m.artifact_id, m] }
      report.artifacts.each do |artifact|
        expect(artifact.migration_action).to eq(manifest_by_id.fetch(artifact.artifact_id).action)
        expect(artifact.migration_reason).to eq(manifest_by_id.fetch(artifact.artifact_id).reason)
      end
    end

    it "computes content_type_distribution/quality_distribution/staleness_flags over the artifacts" do
      source = described_class.new(pipeline:)

      report = source.analyze(sample_ref)

      expect(report.content_type_distribution.values.sum).to eq(report.artifacts.size)
      expect(report.quality_distribution.values.sum).to eq(report.artifacts.size)
      expect(report.staleness_flags).to be_an(Array)
    end

    it "records file_count/artifact_count/images_analyzed/store in metadata" do
      source = described_class.new(pipeline:)

      report = source.analyze(sample_ref, store: false)

      expect(report.metadata[:file_count]).to eq(1)
      expect(report.metadata[:artifact_count]).to eq(3)
      expect(report.metadata[:images_analyzed]).to be(false)
      expect(report.metadata[:store]).to be(false)
    end

    it "never calls review_queue_repo when store: false" do
      review_queue_repo = instance_double(SFL::Store::PgReviewQueueRepository)
      allow(review_queue_repo).to receive(:enqueue)
      source = described_class.new(pipeline:, review_queue_repo:)

      source.analyze(sample_ref, store: false)

      expect(review_queue_repo).not_to have_received(:enqueue)
    end

    it "reports progress via on_progress before each artifact compiles" do
      progress_calls = []
      source = described_class.new(pipeline:, on_progress: -> (**kwargs) { progress_calls << kwargs })

      source.analyze(sample_ref)

      expect(progress_calls.size).to eq(3)
      expect(progress_calls.first).to include(artifact_id: 1, total: 3, source_file: sample_path)
    end

    it "halts early and returns a partial report when stop_requested becomes truthy" do
      calls = 0
      stop = lambda {
        calls += 1
        calls > 1
      }
      source = described_class.new(pipeline:, stop_requested: stop)

      report = source.analyze(sample_ref)

      expect(report.artifacts.size).to eq(1)
    end
  end

  describe "per-file degradation: one malformed section must not abort the whole-corpus run" do
    it "skips the failing artifact, records it in metadata[:skipped], and still assembles the rest" do
      allow(pipeline).to receive(:compile).and_return(
        Success(clauses_for(2, id_prefix: "a")),
        Failure([:pass_one_failed, "a Date-typed title crashed Pass 1"]),
        Success(clauses_for(2, id_prefix: "c"))
      )
      source = described_class.new(pipeline:)

      report = source.analyze(sample_ref)

      expect(report.artifacts.size).to eq(2)
      expect(report.metadata[:skipped_count]).to eq(1)
      expect(report.metadata[:skipped].size).to eq(1)
      expect(report.metadata[:skipped].first).to include(artifact_id: 2, source_file: sample_path)
      expect(report.metadata[:skipped].first[:error]).to include("compile failed")
    end

    it "reports every artifact as done after it compiles or is skipped, the last one included" do
      allow(pipeline).to receive(:compile).and_return(
        Success(clauses_for(2, id_prefix: "a")),
        Failure([:pass_one_failed, "boom"]),
        Success(clauses_for(1, id_prefix: "c"))
      )
      done = []
      source = described_class.new(pipeline:, on_artifact_done: -> (**event) { done << event })

      source.analyze(sample_ref)

      expect(done.map { |event| event.slice(:artifact_id, :total, :failed, :clause_count) }).to eq([
        { artifact_id: 1, total: 3, failed: false, clause_count: 2 },
        { artifact_id: 2, total: 3, failed: true, clause_count: 0 },
        { artifact_id: 3, total: 3, failed: false, clause_count: 1 },
      ])
    end

    it "does not swallow the failure silently — the skip reason is a real message, not a stub" do
      allow(pipeline).to receive(:compile).and_return(Failure([:pass_one_failed, "boom"]))
      source = described_class.new(pipeline:)

      report = source.analyze(sample_ref)

      expect(report.artifacts).to be_empty
      expect(report.metadata[:skipped_count]).to eq(3)
      expect(report.metadata[:skipped].map { |s| s[:error] }).to all(include("boom"))
    end
  end
end
