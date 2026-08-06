# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/sfl/gui/review_queue_view_model"

RSpec.describe SFL::GUI::ReviewQueueViewModel do
  subject(:view_model) { described_class.new(repo:, pipeline:, reviewer_name: "bob") }

  let(:repo) { instance_double(SFL::Store::PgReviewQueueRepository) }
  let(:pipeline) { instance_double(SFL::Core::Pipeline) }

  let(:pending_row) do
    {
      id: "row-1",
      document_id: "doc-1",
      modality: "text",
      reason: "low_quality_score",
      source_file: "notes.md",
      generated_text: "Some flagged text.",
      created_at: Time.now,
    }
  end

  describe "#refresh!" do
    it "populates items from repo.pending, scoped by modality_filter" do
      allow(repo).to receive(:pending).with(modality: nil).and_return(items: [pending_row], total: 1)

      result = view_model.refresh!

      expect(result).to be_success
      expect(view_model.items).to eq([pending_row])
    end

    it "passes modality_filter through when it isn't \"all\"" do
      view_model.modality_filter = "image"
      allow(repo).to receive(:pending).with(modality: "image").and_return(items: [], total: 0)

      view_model.refresh!

      expect(repo).to have_received(:pending).with(modality: "image")
    end

    it "keeps the current selection when it's still present in the refreshed items" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)

      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.refresh!

      expect(view_model.selected_item).to eq(pending_row)
    end

    it "preserves edited_text across a refresh that keeps the selection" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)
      view_model.edited_text = "a reviewer's in-progress correction"

      view_model.refresh!

      expect(view_model.edited_text).to eq("a reviewer's in-progress correction")
    end

    it "clears the selection when the previously-selected row is no longer pending" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)

      allow(repo).to receive(:pending).and_return(items: [], total: 0)
      view_model.refresh!

      expect(view_model.selected_item).to be_nil
      expect(view_model.edited_text).to be_nil
    end

    it "returns Failure without raising when the repo raises Sequel::Error" do
      allow(repo).to receive(:pending).and_raise(Sequel::Error, "connection lost")

      result = view_model.refresh!

      expect(result).to be_failure
    end
  end

  describe "#select" do
    it "sets selected_item and seeds edited_text from generated_text" do
      view_model.select(pending_row)

      expect(view_model.selected_item).to eq(pending_row)
      expect(view_model.edited_text).to eq("Some flagged text.")
    end

    # ItemListControl looks a clicked row up as items[row], which returns nil if
    # the auto-refresh timer shrank items between the repaint and the click.
    it "no-ops instead of raising when handed nil" do
      expect { view_model.select(nil) }.not_to raise_error

      expect(view_model.selected_item).to be_nil
      expect(view_model.edited_text).to be_nil
    end

    it "leaves an existing selection untouched when handed nil" do
      view_model.select(pending_row)

      view_model.select(nil)

      expect(view_model.selected_item).to eq(pending_row)
      expect(view_model.edited_text).to eq("Some flagged text.")
    end
  end

  describe "#detail_kind" do
    it "is nil when nothing is selected" do
      expect(view_model.detail_kind).to be_nil
    end

    it "is :image for modality image" do
      view_model.select(pending_row.merge(modality: "image"))
      expect(view_model.detail_kind).to eq(:image)
    end

    it "is :text for modality text or audio" do
      view_model.select(pending_row.merge(modality: "text"))
      expect(view_model.detail_kind).to eq(:text)

      view_model.select(pending_row.merge(modality: "audio"))
      expect(view_model.detail_kind).to eq(:text)
    end

    it "is :unrecognized for any other modality value" do
      view_model.select(pending_row.merge(modality: "video"))
      expect(view_model.detail_kind).to eq(:unrecognized)
    end
  end

  describe "#approve!" do
    it "calls repo.decide with decision approve and the reviewer name, then refreshes" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)
      allow(repo).to receive(:decide).and_return(pending_row.merge(status: "approved"))
      allow(repo).to receive(:pending).and_return(items: [], total: 0)

      result = view_model.approve!

      expect(repo).to have_received(:decide).with(id: "row-1", decision: "approve", reviewer: "bob")
      expect(result).to be_success
    end

    it "returns Failure without calling decide when nothing is selected" do
      allow(repo).to receive(:decide)

      result = view_model.approve!

      expect(repo).not_to have_received(:decide)
      expect(result).to be_failure
    end
  end

  describe "#reject!" do
    it "calls repo.decide with decision reject" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)
      allow(repo).to receive(:decide).and_return(pending_row.merge(status: "rejected"))
      allow(repo).to receive(:pending).and_return(items: [], total: 0)

      view_model.reject!

      expect(repo).to have_received(:decide).with(id: "row-1", decision: "reject", reviewer: "bob")
    end
  end

  describe "#save_and_recompile!" do
    it "calls pipeline.compile first, and only calls decide(edit) on Success" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)
      view_model.edited_text = "corrected text"
      compile_success = Dry::Monads::Success([:some_annotated_clause])
      allow(pipeline).to receive(:compile)
        .with("corrected text", document_id: "doc-1", store: true, embed: true)
        .and_return(compile_success)
      allow(repo).to receive(:decide).and_return(pending_row.merge(status: "edited"))
      allow(repo).to receive(:pending).and_return(items: [], total: 0)

      result = view_model.save_and_recompile!

      expect(pipeline).to have_received(:compile).with("corrected text", document_id: "doc-1", store: true, embed: true)
      expect(repo).to have_received(:decide).with(id: "row-1", decision: "edit", reviewer: "bob")
      expect(result).to be_success
    end

    it "does not call decide, and returns the Failure, when pipeline.compile fails" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)
      view_model.edited_text = "corrected text"
      compile_failure = Dry::Monads::Failure([:pass_one_failed, "sidecar crashed"])
      allow(pipeline).to receive(:compile).and_return(compile_failure)
      allow(repo).to receive(:decide)

      result = view_model.save_and_recompile!

      expect(repo).not_to have_received(:decide)
      expect(result).to eq(compile_failure)
    end

    it "preserves edited_text after a failed recompile" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)
      view_model.edited_text = "corrected text"
      allow(pipeline).to receive(:compile).and_return(Dry::Monads::Failure([:pass_one_failed, "boom"]))

      view_model.save_and_recompile!

      expect(view_model.edited_text).to eq("corrected text")
    end

    it "returns Failure without calling pipeline.compile when nothing is selected" do
      allow(pipeline).to receive(:compile)

      result = view_model.save_and_recompile!

      expect(pipeline).not_to have_received(:compile)
      expect(result).to be_failure
    end

    # pipeline.compile reaches the network; an exception escaping here would
    # unwind into the libui event loop and take the window down.
    it "converts an exception raised by pipeline.compile into a Failure" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)
      view_model.edited_text = "corrected text"
      allow(pipeline).to receive(:compile).and_raise(Timeout::Error, "LLM timed out")
      allow(repo).to receive(:decide)

      result = nil
      expect { result = view_model.save_and_recompile! }.not_to raise_error

      expect(result).to be_failure
      expect(result.failure).to eq("LLM timed out")
      expect(repo).not_to have_received(:decide)
    end

    it "preserves edited_text and the selection after a raised recompile" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)
      view_model.edited_text = "corrected text"
      allow(pipeline).to receive(:compile).and_raise(StandardError, "connection reset")

      view_model.save_and_recompile!

      expect(view_model.edited_text).to eq("corrected text")
      expect(view_model.selected_item).to eq(pending_row)
    end

    it "logs the raised exception via the injected logger" do
      logger = instance_spy(SFL::Core::Ports::StandardLogger)
      vm = described_class.new(repo:, pipeline:, reviewer_name: "bob", logger:)
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      vm.select(pending_row)
      allow(pipeline).to receive(:compile).and_raise(StandardError, "connection reset")

      vm.save_and_recompile!

      expect(logger).to have_received(:error)
    end
  end
end
