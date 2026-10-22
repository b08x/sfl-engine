# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::CLI::CompositeProgress do
  subject(:progress) { described_class.new(sink:) }

  let(:run_log) { SFL::Core::Ports::Fake::RunLog.new }
  let(:sink) { SFL::CLI::PgRunProgressSink.new(run_log:, run_id: "r", kind: "annotate", heartbeat_every: nil) }

  it "starts the run on the first turn, names the speaker and counts finished turns (fact 21)" do
    progress.start(turn_id: 1, total: 2, speaker: "Alice")
    progress.advance(turn_id: 1, total: 2, defaulted: 0, clause_count: 1)
    progress.start(turn_id: 2, total: 2, speaker: "Bob")

    expect(run_log.rows["r"]).to include(total: 2, done: 1, current_item: "Bob")
  end

  it "counts every knowledge-base artifact once it is done, the last one included" do
    progress.artifact(artifact_id: 1, total: 2, title: "a", source_file: "/v/a.md")
    progress.artifact_done(artifact_id: 1, total: 2, failed: false, clause_count: 3, defaulted: 0)
    progress.artifact(artifact_id: 2, total: 2, title: "b", source_file: "/v/b.md")
    progress.artifact_done(artifact_id: 2, total: 2, failed: true, clause_count: 0, defaulted: 0)

    expect(run_log.rows["r"]).to include(total: 2, done: 2, failed: 1, current_item: "/v/b.md")
  end

  it "passes clause and defaulted counts to a sink that takes notes (fact 49)" do
    board = SFL::Dashboard::Board.new(SFL::Dashboard::State.initial(run_id: "r", kind: "annotate", collection: nil,
      models: [], documents: 1, now: Time.at(0)))
    noted = described_class.new(sink: SFL::Dashboard::Sink.new(inner: sink, board:))
    noted.start(turn_id: 1, total: 1, speaker: "A")
    noted.advance(turn_id: 1, total: 1, clause_count: 4, defaulted: 1)

    expect(board.state).to have_attributes(clauses: 4, defaulted: 1, sections_done: 1, documents_done: 1)
  end

  it "works with a sink that has no #item or #note" do
    plain = described_class.new(sink: SFL::Core::Ports::Null::ProgressSink.new)

    expect do
      plain.start(turn_id: 1, total: 1, speaker: "A")
      plain.advance(turn_id: 1, total: 1, clause_count: 1, defaulted: 0)
      plain.artifact_done(artifact_id: 1, total: 1, failed: false)
    end.not_to raise_error
  end
end
