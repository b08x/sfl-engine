# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe SFL::TUI::Browse::Commands do
  let(:source) { TUISpecSupport.source }
  let(:review_queue) { instance_spy(SFL::Store::PgReviewQueueRepository) }
  let(:run_log) { SFL::Core::Ports::Fake::RunLog.new }
  let(:editor) { SFL::Core::Ports::Fake::Editor.new(result: "Edited text.") }
  let(:compiled) { [] }
  let(:recompiler) do
    lambda do |text, section_id:|
      compiled << [text, section_id]
      Dry::Monads::Success(section_id)
    end
  end
  let(:services) do
    SFL::TUI::Services.null(source:, review_queue:, run_log:, editor:, recompiler:, reviewer: "ana", run_id: -> { "run-1" })
  end
  let(:item) { TUISpecSupport.content_reviews.first }

  it "loads the tree and both review states" do
    message = described_class.load(services).call

    expect(message.tree.roots).to eq(["c:1", "c:2"])
    expect(message.reviews.pending?("paper.md#method")).to be(true)
  end

  it "loads one section's clauses" do
    expect(described_class.load_clauses(services, "paper.md#method").call.clauses.map { |row| row[:id] }).to eq(["m1"])
  end

  # Fact 30: decisions go through the review queue repository.
  it "records approve and reject through the review queue under the reviewer's name" do
    message = described_class.decide(services, item, "approve").call

    expect(review_queue).to have_received(:decide).with(id: "r1", decision: "approve", reviewer: "ana")
    expect(message).to eq(SFL::TUI::Messages::Reviewed.new("approve: paper.md#method"))
  end

  it "refuses a decision when no reviewer name is set" do
    message = described_class.decide(services.with(reviewer: nil), item, "reject").call

    expect(message).to be_a(SFL::TUI::Messages::Failed)
    expect(message.detail).to include("SFL_REVIEWER_NAME")
    expect(review_queue).not_to have_received(:decide)
  end

  # Fact 31: edit opens $EDITOR, recompiles as a recompile run, records the edit.
  it "edits in the editor, recompiles the section as a recompile run and records an edit decision" do
    message = described_class.edit(services, item, "papers").call

    expect(editor.edited).to eq(["A chart of results."])
    expect(compiled).to eq([["Edited text.", "paper.md#method"]])
    expect(run_log.list.first).to include(run_id: "run-1", kind: "recompile", collection: "papers", status: "finished",
      done: 1, total: 1)
    expect(review_queue).to have_received(:decide).with(id: "r1", decision: "edit", reviewer: "ana")
    expect(message).to be_a(SFL::TUI::Messages::Reviewed)
  end

  it "marks the recompile run failed and records no decision when the compile fails" do
    failing = services.with(recompiler: -> (_text, section_id:) { Dry::Monads::Failure("pass 2 down #{section_id}") })
    message = described_class.edit(failing, item, "papers").call

    expect(message.detail).to eq("pass 2 down paper.md#method")
    expect(run_log.list.first).to include(status: "failed", failed: 1)
    expect(review_queue).not_to have_received(:decide)
  end

  it "turns an editor error into a failure message" do
    broken = services.with(editor: SFL::Core::Ports::Fake::Editor.new(result: -> (_text) { raise SFL::Error, "no editor" }))

    expect(described_class.edit(broken, item, "papers").call.detail).to eq("SFL::Error: no editor")
  end

  # Fact 32
  it "opens the item's source file through the opener" do
    opener = SFL::Core::Ports::Fake::Opener.new

    expect(described_class.open(services.with(opener:), item).call).to eq(SFL::TUI::Messages::Status.new("opened /data/figure.png"))
    expect(opener.opened).to eq(["/data/figure.png"])
  end

  # Fact 71: under kitty the open-viewer key shows the image with kitten icat.
  it "shows the image inline through the terminal host when it can, without the external viewer" do
    opener = SFL::Core::Ports::Fake::Opener.new
    host = SFL::Core::Ports::Fake::TerminalHost.new

    message = described_class.open(services.with(opener:, terminal_host: host), item).call

    expect(message).to eq(SFL::TUI::Messages::Status.new("shown /data/figure.png with kitten icat"))
    expect(host.images).to eq(["/data/figure.png"])
    expect(opener.opened).to be_empty
  end

  it "falls back to the external viewer when the terminal host fails" do
    opener = SFL::Core::Ports::Fake::Opener.new
    host = SFL::Core::Ports::Fake::TerminalHost.new(error: "kitty remote control failed: refused")

    message = described_class.open(services.with(opener:, terminal_host: host), item).call

    expect(message.text).to eq("opened /data/figure.png")
    expect(opener.opened).to eq(["/data/figure.png"])
  end

  # Fact 65: TUI recompile runs record the Boot llm_config header.
  it "records the run header's models on the recompile run" do
    models = { "pass_two_annotation" => { "provider" => "openrouter", "model" => "m", "source" => "env" } }

    described_class.edit(services.with(run_models: models), item, "papers").call

    expect(run_log.list.first).to include(models:)
  end

  it "exports through the exporter" do
    exporter = instance_double(SFL::Export::Exporter, call: { path: "/out/x.md", count: 3 })

    message = described_class.export(services.with(exporter:), [], :markdown).call

    expect(message).to eq(SFL::TUI::Messages::Exported.new(path: "/out/x.md", count: 3))
  end
end
