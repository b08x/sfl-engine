# frozen_string_literal: true

require "spec_helper"
require "glimmer-dsl-libui"
require_relative "../../lib/sfl/gui/review_queue_app"

# Only the plain-Ruby half of #initialize is exercised here. Nothing in this
# file builds a window, calls #launch, or touches a Glimmer control — all of
# that needs a display. What made this testable at all is SIFT S-1: repo,
# pipeline and logger are now injectable, so Boot.call (which opens a DB
# connection and validates LLM credentials) is never reached.
RSpec.describe SFL::GUI::ReviewQueueApp do
  subject(:app) { described_class.new(repo:, pipeline:, logger:) }

  let(:repo) { instance_double(SFL::Store::PgReviewQueueRepository) }
  let(:pipeline) { instance_double(SFL::Core::Pipeline) }
  let(:logger) { instance_spy(SFL::Core::Ports::StandardLogger) }

  let(:pending_row) do
    { id: "row-1", document_id: "doc-1", modality: "text", generated_text: "flagged text" }
  end

  around do |example|
    original = ENV.fetch("SFL_REVIEWER_NAME", nil)
    example.run
  ensure
    ENV["SFL_REVIEWER_NAME"] = original
  end

  before do
    ENV["SFL_REVIEWER_NAME"] = "bob"
    allow(repo).to receive(:pending).and_return(items: [], total: 0)
  end

  describe "reviewer attribution (SIFT F-3)" do
    it "fails fast instead of building an app that writes NULL reviewers" do
      ENV.delete("SFL_REVIEWER_NAME")

      expect { app }.to raise_error(described_class::MissingReviewerNameError, /SFL_REVIEWER_NAME must be set/)
    end

    it "raises a subclass of SFL::Error so callers can rescue it with the rest of the app's errors" do
      ENV.delete("SFL_REVIEWER_NAME")

      expect { app }.to raise_error(SFL::Error)
    end

    it "treats an empty reviewer name as unset" do
      ENV["SFL_REVIEWER_NAME"] = ""

      expect { app }.to raise_error(described_class::MissingReviewerNameError)
    end

    it "treats a whitespace-only reviewer name as unset" do
      ENV["SFL_REVIEWER_NAME"] = "   "

      expect { app }.to raise_error(described_class::MissingReviewerNameError)
    end

    # The whole point of checking before build_collaborators: booting the DB and
    # the LLM only to then refuse to start wastes seconds and buries the reason.
    it "refuses before booting the database or the LLM" do
      ENV.delete("SFL_REVIEWER_NAME")
      allow(SFL::Boot).to receive(:call)

      expect { app }.to raise_error(described_class::MissingReviewerNameError)
      expect(SFL::Boot).not_to have_received(:call)
    end

    it "attributes decisions to the reviewer named in the environment" do
      ENV["SFL_REVIEWER_NAME"] = "alice"
      allow(repo).to receive_messages(pending: { items: [pending_row], total: 1 }, decide: pending_row)

      app.viewmodel.select_row(0)
      app.viewmodel.approve!

      expect(repo).to have_received(:decide).with(id: "row-1", decision: "approve", reviewer: "alice")
    end
  end

  describe "collaborator injection (SIFT S-1)" do
    it "never calls Boot when repo and pipeline are both supplied" do
      allow(SFL::Boot).to receive(:call)

      app

      expect(SFL::Boot).not_to have_received(:call)
    end

    it "builds a viewmodel" do
      expect(app.viewmodel).to be_a(SFL::GUI::ReviewQueueViewModel)
    end

    it "wires the injected pipeline into the viewmodel's recompile path" do
      allow(repo).to receive_messages(pending: { items: [pending_row], total: 1 }, decide: pending_row)
      allow(pipeline).to receive(:compile).and_return(Dry::Monads::Success([]))

      app.viewmodel.select_row(0)
      app.viewmodel.save_and_recompile!

      expect(pipeline).to have_received(:compile).with("flagged text", document_id: "doc-1", store: true, embed: true)
    end

    it "uses the injected logger rather than building a StandardLogger" do
      expect(app.logger).to be(logger)
    end
  end

  describe "startup refresh" do
    it "populates the viewmodel from the repo before the window is ever built" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)

      expect(app.viewmodel.items).to eq([pending_row])
    end

    it "does not log a warning when the startup refresh succeeds" do
      app

      expect(logger).not_to have_received(:warn)
    end

    # An empty queue and an unreachable database look identical on screen, so
    # the reason has to reach the terminal (#log_refresh_failure).
    it "logs a warning but still constructs when the startup refresh fails" do
      allow(repo).to receive(:pending).and_raise(Sequel::Error, "connection lost")

      expect { app }.not_to raise_error
      # Twice, and deliberately so: ReviewQueueViewModel#refresh! logs the raw
      # exception in its rescue, then #log_refresh_failure names the phase.
      expect(logger).to have_received(:warn).twice
    end

    # SIFT F-2: the rescue in ReviewQueueViewModel#refresh! is no longer
    # Sequel-specific, so a non-Sequel outage no longer escapes into the caller.
    it "survives a startup failure that is not a Sequel::Error" do
      allow(repo).to receive(:pending).and_raise(Errno::ECONNREFUSED)

      expect { app }.not_to raise_error
      # Twice, and deliberately so: ReviewQueueViewModel#refresh! logs the raw
      # exception in its rescue, then #log_refresh_failure names the phase.
      expect(logger).to have_received(:warn).twice
    end
  end
end
