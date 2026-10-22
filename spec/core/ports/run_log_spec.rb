# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::RunLog do
  let(:log) { Class.new { include SFL::Core::Ports::RunLog }.new }

  it "requires every method from an adapter" do
    expect { log.start(run_id: "r", kind: "ingest", collection: nil, total: 1, pid: 1) }.to raise_error(NotImplementedError)
    expect { log.advance("r", done: 1) }.to raise_error(NotImplementedError)
    expect { log.heartbeat("r") }.to raise_error(NotImplementedError)
    expect { log.finish("r", status: "finished") }.to raise_error(NotImplementedError)
    expect { log.list }.to raise_error(NotImplementedError)
    expect { log.stalled }.to raise_error(NotImplementedError)
  end

  it "names the run kinds" do
    expect(described_class::KINDS).to eq(%w[ingest annotate export recompile])
  end
end
