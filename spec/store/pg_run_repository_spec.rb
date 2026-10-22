# frozen_string_literal: true

require "spec_helper"

# Facts 20 to 22 against Postgres.
RSpec.describe SFL::Store::PgRunRepository do
  subject(:repo) { described_class.new(db, clock: -> { clock_time.first }, alive:, stall_after: 30) }

  let(:db) { SFL::Store::StoreTestDb.db }
  let(:now) { Time.utc(2026, 10, 17, 12) }
  let(:clock_time) { [now] }
  let(:alive) { -> (pid) { pid != 2 } }

  before { SFL::Store::StoreTestDb.clean! }

  def start(run_id, pid: 1, kind: "ingest") = repo.start(run_id:, kind:, collection: "c", total: 5, pid:)

  it "writes one row per run id with kind, collection, status, counts, pid and times (fact 20)" do
    start("run-1")
    start("run-1")

    expect(db[:runs].all).to contain_exactly(hash_including(
      run_id: "run-1", kind: "ingest", collection: "c", status: "running", total: 5, done: 0, failed: 0, pid: 1,
      started_at: now, heartbeat_at: now, finished_at: nil
    ))
  end

  it "records the effective model per task in the run header (fact 65)" do
    models = { "embedding" => { "provider" => "ollama", "model" => "e", "source" => "env" } }
    repo.start(run_id: "run-m", kind: "annotate", collection: nil, total: 1, pid: 1, models:)
    start("run-n")

    expect(db[:runs].where(run_id: "run-m").get(:models).to_h).to eq(models)
    expect(db[:runs].where(run_id: "run-n").get(:models)).to be_nil
  end

  it "records progress as the run advances and its finish (fact 21)" do
    start("run-1")
    clock_time[0] = now + 3
    repo.advance("run-1", done: 2, failed: 1, current_item: "Alice", ignored: true)
    repo.finish("run-1", status: "finished")

    expect(db[:runs].first).to include(done: 2, failed: 1, current_item: "Alice", status: "finished",
      heartbeat_at: now + 3, finished_at: now + 3)
  end

  it "rejects an unknown kind" do
    expect { start("run-1", kind: "bogus") }.to raise_error(ArgumentError, /kind/)
  end

  it "lists newest first, showing stalled and dead runs (fact 22)" do
    start("stalled")
    clock_time[0] = now + 1
    start("dead", pid: 2)
    clock_time[0] = now + 2
    start("done")
    repo.finish("done", status: "finished")
    clock_time[0] = now + 40
    start("fresh")

    expect(repo.list.map { |row| [row[:run_id], row[:state]] })
      .to eq([%w[fresh running], %w[done finished], %w[dead dead], %w[stalled stalled]])
    expect(repo.stalled.map { |row| row[:run_id] }).to contain_exactly("dead", "stalled")
  end

  it "keeps a run alive with a heartbeat" do
    start("run-1")
    clock_time[0] = now + 40
    repo.heartbeat("run-1")

    expect(repo.list.first[:state]).to eq("running")
  end
end
