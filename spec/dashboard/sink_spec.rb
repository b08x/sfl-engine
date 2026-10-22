# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Dashboard::Sink do
  subject(:sink) { described_class.new(inner:, board:) }

  let(:run_log) { SFL::Core::Ports::Fake::RunLog.new }
  let(:inner) { SFL::CLI::PgRunProgressSink.new(run_log:, run_id: "r", kind: "ingest", heartbeat_every: nil) }
  let(:board) do
    SFL::Dashboard::Board.new(SFL::Dashboard::State.initial(run_id: "r", kind: "ingest", collection: nil, models: [],
      documents: 1, now: Time.at(0)))
  end

  it "records each call on the board and forwards it to the runs table" do
    sink.start(2)
    sink.item("a.md")
    sink.advance(by: 1, failed: 1)
    sink.note(clauses: 3, defaulted: 1)
    sink.finish(status: "interrupted")

    expect(board.state).to have_attributes(sections_total: 2, sections_done: 1, failures: 1, clauses: 3, defaulted: 1,
      current_item: "a.md", outcome: "interrupted")
    expect(run_log.rows["r"]).to include(total: 2, done: 1, failed: 1, current_item: "a.md", status: "interrupted")
  end

  it "skips #item on a sink that has none" do
    plain = described_class.new(inner: SFL::Core::Ports::Null::ProgressSink.new, board:)
    plain.item("x")
    plain.advance

    expect(board.state.current_item).to eq("x")
  end
end
