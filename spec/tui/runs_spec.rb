# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe SFL::TUI::Runs do
  let(:now) { Time.new(2026, 10, 17, 12, 0, 0) }
  let(:clock) { [now - 60] }
  let(:run_log) do
    times = clock
    SFL::Core::Ports::Fake::RunLog.new(clock: -> { times.first }, alive: -> (pid) { pid != 99 })
  end
  let(:services) { SFL::TUI::Services.null(run_log:) }

  # An ingest that finished, a recompile and an export from the TUI, and an
  # annotation whose process is gone, started a second apart.
  def record_runs
    [
      ["ingest-1", "ingest", "papers", 1],
      ["recompile-1", "recompile", "papers", 1],
      ["export-1", "export", nil, 1],
      ["annotate-1", "annotate", "notes", 99],
    ].each_with_index do |(run_id, kind, collection, pid), index|
      clock[0] = now - 60 + index
      run_log.start(run_id:, kind:, collection:, total: 4, pid:)
    end
    clock[0] = now
    run_log.advance("ingest-1", done: 4)
    run_log.finish("ingest-1", status: "finished")
    run_log.advance("recompile-1", done: 1, current_item: "paper.md#intro")
    run_log.finish("export-1", status: "finished")
  end

  def loaded
    record_runs
    message = described_class.init(services).call
    described_class.update(described_class.initial, message, services).first
  end

  def screen(state) = TUISpecSupport.render(width: 120, height: 10) { |frame, tui| described_class.render(state, frame, frame.area, tui) }

  it "answers the tab protocol" do
    expect(described_class::TITLE).to eq("Runs")
    expect(described_class.handles?(SFL::TUI::Messages::RunsLoaded.new([]))).to be(true)
    expect(described_class.handles?(SFL::TUI::Messages::Tick.new(now))).to be(true)
    expect(described_class.handles?(TUISpecSupport.key("x"))).to be(false)
    expect(described_class.capturing?(described_class.initial)).to be(false)
    expect(described_class.help(nil)).to include("r reload")
    expect(described_class.status(described_class.initial)).to be_nil
    initial = described_class.initial
    expect(described_class.update(initial, :other, services)).to eq([initial, nil])
  end

  it "lists runs newest first with kind, collection, state and progress (fact 53)" do
    lines = screen(loaded.with(now:))
    body = lines.drop(2)

    expect(lines[1]).to include("started", "kind", "collection", "state", "progress")
    expect(body[0]).to include("annotate", "notes", "dead", "0/4 (0%)")
    expect(body[1]).to include("export", "finished")
    expect(body[2]).to include("recompile", "papers", "running", "1/4 (25%)", "paper.md#intro")
    expect(body[3]).to include("ingest", "papers", "finished", "4/4 (100%)")
  end

  it "shows the recompile run an edit starts (fact 31) and the export run (fact 45)" do
    kinds = loaded.rows.map { |row| row[:kind] }

    expect(kinds).to include("recompile", "export")
    expect(screen(loaded.with(now:)).join("\n")).to include("recompile", "export")
  end

  it "counts runs needing attention in the status" do
    expect(described_class.status(loaded)).to eq("4 runs, 1 stalled, dead or failed")
  end

  it "polls the run log on a Tick every POLL_SECONDS (fact 53)" do
    state = described_class.initial
    state, first = described_class.update(state, SFL::TUI::Messages::Tick.new(now), services)
    state, early = described_class.update(state, SFL::TUI::Messages::Tick.new(now + 1), services)
    state, due = described_class.update(state, SFL::TUI::Messages::Tick.new(now + described_class::POLL_SECONDS), services)

    expect(first).to be_a(Proc)
    expect(early).to be_nil
    expect(due).to be_a(Proc)
    expect(state.now).to eq(now + described_class::POLL_SECONDS)
    record_runs
    expect(due.call.rows.size).to eq(4)
  end

  it "moves the cursor within the rows and reloads on r" do
    state = loaded
    state, = described_class.update(state, TUISpecSupport.key("down"), services)
    state, = described_class.update(state, TUISpecSupport.key("j"), services)
    expect(state.cursor).to eq(2)

    state, = described_class.update(state, TUISpecSupport.key("up"), services)
    state, reload = described_class.update(state, TUISpecSupport.key("r"), services)
    expect(state.cursor).to eq(1)
    expect(reload.call).to be_a(SFL::TUI::Messages::RunsLoaded)
    expect(described_class.update(state, TUISpecSupport.key("x"), services)).to eq([state, nil])
  end

  it "keeps the cursor inside a shorter list" do
    state = loaded.with(cursor: 3)

    expect(described_class.update(state, SFL::TUI::Messages::RunsLoaded.new([]), services).first.cursor).to eq(0)
  end

  it "reports a failing run log through the failure channel" do
    broken = SFL::TUI::Services.null(run_log: instance_double(SFL::Store::PgRunRepository))
    allow(broken.run_log).to receive(:list).and_raise(Sequel::DatabaseConnectionError, "down")

    expect(described_class.load(broken).call).to be_a(SFL::TUI::Messages::Failed)
  end

  it "draws an empty table before the first load" do
    expect(screen(described_class.initial).first).to include("Runs")
  end
end
