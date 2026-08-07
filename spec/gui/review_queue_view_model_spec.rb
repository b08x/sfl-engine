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

    # SIFT F-2: this runs at startup and on every tick of the 10s auto-refresh
    # timer, where anything escaping unwinds into the libui event loop and kills
    # the window. A DB outage is not only Sequel::Error — socket, DNS and
    # connection-pool failures each have their own class.
    it "returns Failure without raising when the repo raises a non-Sequel error" do
      allow(repo).to receive(:pending).and_raise(Errno::ECONNREFUSED)

      result = nil
      expect { result = view_model.refresh! }.not_to raise_error

      expect(result).to be_failure
    end

    it "logs the non-Sequel failure via the injected logger" do
      logger = instance_spy(SFL::Core::Ports::StandardLogger)
      vm = described_class.new(repo:, pipeline:, reviewer_name: "bob", logger:)
      allow(repo).to receive(:pending).and_raise(Errno::EHOSTUNREACH)

      vm.refresh!

      expect(logger).to have_received(:warn)
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

  # SIFT S-2: ItemListControl used to script `select(viewmodel.items[row])`.
  # The index-to-item lookup lives here now, so it can be tested at all.
  describe "#select_row" do
    let(:other_row) { pending_row.merge(id: "row-2", generated_text: "Another flagged text.") }

    before { view_model.items = [pending_row, other_row] }

    it "selects the item at the given index" do
      view_model.select_row(1)

      expect(view_model.selected_item).to eq(other_row)
      expect(view_model.edited_text).to eq("Another flagged text.")
    end

    # The reason #select's nil-guard exists: the 10s auto-refresh timer can
    # shrink items between a table repaint and the click it was repainted for.
    it "no-ops instead of raising when the index is past the end of items" do
      expect { view_model.select_row(99) }.not_to raise_error

      expect(view_model.selected_item).to be_nil
    end

    it "no-ops when items is empty" do
      view_model.items = []

      expect { view_model.select_row(0) }.not_to raise_error
      expect(view_model.selected_item).to be_nil
    end

    it "leaves an existing selection untouched when the index is out of bounds" do
      view_model.select_row(0)

      view_model.select_row(99)

      expect(view_model.selected_item).to eq(pending_row)
    end

    # Array#[] would read -1 as "the last row"; selecting nothing is the only
    # defensible reading of a negative row index.
    it "selects nothing rather than the last row when handed a negative index" do
      view_model.select_row(-1)

      expect(view_model.selected_item).to be_nil
    end

    it "no-ops when handed nil" do
      expect { view_model.select_row(nil) }.not_to raise_error

      expect(view_model.selected_item).to be_nil
    end
  end

  # SIFT F-1 follow-up. Glimmer's observers notify synchronously in the calling
  # thread (glimmer-2.8.2 observable_model.rb#notify_observers), so assigning an
  # observed attribute pushes straight into a libui C call on that thread.
  # save_and_recompile! is therefore split in two: the network-bound half that
  # mutates nothing (safe on a worker thread) and the state-mutating half that
  # must run on the main thread via queue_main.
  describe "#compile_for_recompile" do
    before do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)
      view_model.edited_text = "corrected text"
    end

    it "returns pipeline.compile's Result for the edited text" do
      compile_success = Dry::Monads::Success([:clause])
      allow(pipeline).to receive(:compile)
        .with("corrected text", document_id: "doc-1", store: true, embed: true)
        .and_return(compile_success)

      expect(view_model.compile_for_recompile).to eq(compile_success)
    end

    # The whole reason this method exists: it is what runs on the worker thread,
    # so it must not touch a single Glimmer-observed attribute.
    it "mutates no observed attribute, so it is safe off the main thread" do
      allow(pipeline).to receive(:compile).and_return(Dry::Monads::Success([:clause]))
      before_state = [view_model.items, view_model.selected_item, view_model.edited_text]

      view_model.compile_for_recompile

      expect([view_model.items, view_model.selected_item, view_model.edited_text]).to eq(before_state)
    end

    it "never records a decision or refreshes" do
      allow(pipeline).to receive(:compile).and_return(Dry::Monads::Success([:clause]))
      allow(repo).to receive(:decide)

      view_model.compile_for_recompile

      expect(repo).not_to have_received(:decide)
      expect(repo).not_to have_received(:pending) # #refresh! is the only caller
    end

    it "returns Failure without calling pipeline.compile when nothing is selected" do
      view_model.selected_item = nil
      allow(pipeline).to receive(:compile)

      expect(view_model.compile_for_recompile).to be_failure
      expect(pipeline).not_to have_received(:compile)
    end

    it "converts a raised pipeline exception into a Failure" do
      allow(pipeline).to receive(:compile).and_raise(Timeout::Error, "LLM timed out")

      result = nil
      expect { result = view_model.compile_for_recompile }.not_to raise_error

      expect(result).to be_failure
      expect(result.failure).to eq("LLM timed out")
    end
  end

  describe "#finish_recompile!" do
    before do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)
    end

    it "records an edit decision and refreshes when handed a successful compile" do
      allow(repo).to receive_messages(decide: pending_row.merge(status: "edited"), pending: { items: [], total: 0 })

      result = view_model.finish_recompile!(Dry::Monads::Success([:clause]), compiled_item_id: "row-1")

      expect(repo).to have_received(:decide).with(id: "row-1", decision: "edit", reviewer: "bob")
      expect(result).to be_success
    end

    it "short-circuits and returns the compile Failure without recording a decision" do
      compile_failure = Dry::Monads::Failure([:pass_one_failed, "sidecar crashed"])
      allow(repo).to receive(:decide)

      result = view_model.finish_recompile!(compile_failure, compiled_item_id: "row-1")

      expect(repo).not_to have_received(:decide)
      expect(result).to eq(compile_failure)
    end

    # The queue_main callback runs after the compile finished, by which point
    # the 10s auto-refresh timer may have resolved the row out from under it.
    it "returns Failure rather than raising when the selection vanished mid-compile" do
      view_model.selected_item = nil
      allow(repo).to receive(:decide)

      result = nil
      expect do
        result = view_model.finish_recompile!(Dry::Monads::Success([:clause]), compiled_item_id: "row-1")
      end.not_to raise_error

      expect(result).to be_failure
      expect(repo).not_to have_received(:decide)
    end

    it "returns Failure without raising when recording the decision fails" do
      allow(repo).to receive(:decide).and_raise(Errno::ECONNREFUSED)

      result = nil
      expect do
        result = view_model.finish_recompile!(Dry::Monads::Success([:clause]), compiled_item_id: "row-1")
      end.not_to raise_error

      expect(result).to be_failure
    end

    # SIFT follow-up: the table stays interactive during a background compile,
    # so the user can click a different row before it finishes. Without this
    # check, decide! would record the edit against whatever is selected when
    # the compile completes rather than the row that was actually compiled.
    it "returns Failure and does not record a decision when the selection changed mid-compile" do
      other_row = pending_row.merge(id: "row-2")
      allow(repo).to receive_messages(pending: { items: [other_row], total: 1 }, decide: other_row)
      view_model.select(other_row) # user clicked a different row while the compile was in flight

      result = view_model.finish_recompile!(Dry::Monads::Success([:clause]), compiled_item_id: "row-1")

      expect(result).to be_failure
      expect(result.failure).to eq(SFL::GUI::ReviewQueueViewModel::SELECTION_CHANGED_MESSAGE)
      expect(repo).not_to have_received(:decide)
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

    # SIFT F-2: same widened rescue as #refresh!, in the private #decide! both
    # approve!/reject!/save_and_recompile! funnel through.
    it "returns Failure without raising when decide raises a non-Sequel error" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)
      allow(repo).to receive(:decide).and_raise(Errno::ECONNREFUSED)

      result = nil
      expect { result = view_model.approve! }.not_to raise_error

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

    # SIFT F-1 follow-up: this method is now a thin composition of
    # #compile_for_recompile + #finish_recompile!. Every example in this block
    # is unchanged from before that split and still passes, which is the actual
    # evidence that the composition is behaviour-preserving.
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
