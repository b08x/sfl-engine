# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Fake::RunLog do
  let(:now) { Time.utc(2026, 10, 17, 12) }
  let(:clock_time) { [now] }
  let(:alive_pids) { [1] }
  let(:log) do
    described_class.new(clock: -> { clock_time.first }, alive: -> (pid) { alive_pids.include?(pid) }, stall_after: 30)
  end

  it "records progress and the finish" do
    log.start(run_id: "r", kind: "ingest", collection: "c", total: 3, pid: 1)
    log.advance("r", done: 2, current_item: "turn 2")
    log.finish("r", status: "finished")

    expect(log.list.first).to include(done: 2, current_item: "turn 2", status: "finished", state: "finished")
  end

  it "lists stalled and dead runs (fact 22)" do
    log.start(run_id: "slow", kind: "ingest", collection: nil, total: 1, pid: 1)
    log.start(run_id: "gone", kind: "annotate", collection: nil, total: 1, pid: 2)
    log.start(run_id: "fresh", kind: "annotate", collection: nil, total: 1, pid: 1)
    clock_time[0] = now + 40
    log.heartbeat("fresh")

    expect(log.stalled.to_h { |row| [row[:run_id], row[:state]] }).to eq("slow" => "stalled", "gone" => "dead")
  end
end
