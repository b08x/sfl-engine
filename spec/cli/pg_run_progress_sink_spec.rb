# frozen_string_literal: true

require "spec_helper"

# Facts 20 and 21: the sink writes the run's progress to the RunLog.
RSpec.describe SFL::CLI::PgRunProgressSink do
  subject(:sink) { described_class.new(run_log:, run_id: "run-1", kind: "annotate", collection: "c", pid: 9, heartbeat_every: nil) }

  let(:run_log) { SFL::Core::Ports::Fake::RunLog.new }

  it "implements the ProgressSink port" do
    expect(sink).to be_a(SFL::Core::Ports::ProgressSink)
  end

  it "creates the run on the first start and raises its total on later starts" do
    sink.start(3)
    sink.start(2)

    expect(run_log.rows["run-1"]).to include(kind: "annotate", collection: "c", pid: 9, total: 5, status: "running")
  end

  it "writes done, failed and the current item as the run advances" do
    sink.start(3)
    sink.item("Alice")
    sink.advance
    sink.advance(by: 1, failed: 1)

    expect(run_log.rows["run-1"]).to include(done: 2, failed: 1, current_item: "Alice")
  end

  it "finishes the run with the given status" do
    sink.start(1)
    sink.finish(status: "interrupted")

    expect(run_log.rows["run-1"][:status]).to eq("interrupted")
  end

  it "writes nothing on finish when the run never started" do
    sink.finish

    expect(run_log.rows).to be_empty
  end

  describe "heartbeat" do
    subject(:sink) { described_class.new(run_log:, run_id: "run-1", kind: "ingest", heartbeat_every: 0.01) }

    it "beats in the background while the run is open and stops on finish" do
      allow(run_log).to receive(:heartbeat).and_call_original
      sink.start(1)
      sleep 0.05
      sink.finish

      expect(run_log).to have_received(:heartbeat).with("run-1").at_least(:once)
    end
  end
end
