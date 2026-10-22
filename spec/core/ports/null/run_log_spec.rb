# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Null::RunLog do
  subject(:log) { described_class.new }

  it "accepts every write and lists no runs" do
    log.start(run_id: "r", kind: "ingest", collection: nil, total: 1, pid: 1)
    log.advance("r", done: 1)
    log.heartbeat("r")
    log.finish("r", status: "finished")

    expect([log.list, log.stalled]).to eq([[], []])
  end
end
