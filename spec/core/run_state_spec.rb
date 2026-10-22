# frozen_string_literal: true

require "spec_helper"

# Fact 22: stalled and dead classification, with an injectable clock and a
# Process.kill(0) seam.
RSpec.describe SFL::Core::RunState do
  let(:now) { Time.utc(2026, 10, 17, 12, 0, 0) }
  let(:alive) { -> (_pid) { true } }

  def row(status: "running", heartbeat_at: now, pid: 42) = { status:, heartbeat_at:, pid: }

  it "keeps a running row with a fresh heartbeat as running" do
    expect(described_class.classify(row(heartbeat_at: now - 5), now:, alive:)).to eq("running")
  end

  it "shows a running row whose heartbeat is older than the threshold as stalled" do
    expect(described_class.classify(row(heartbeat_at: now - 31), now:, alive:, stall_after: 30)).to eq("stalled")
  end

  it "shows a running row whose process no longer exists as dead" do
    expect(described_class.classify(row, now:, alive: -> (_pid) { false })).to eq("dead")
  end

  it "keeps a finished row's status whatever its heartbeat" do
    expect(described_class.classify(row(status: "finished", heartbeat_at: now - 999), now:, alive:)).to eq("finished")
  end

  describe "PID_ALIVE" do
    it "is true for this process and false for a pid that does not exist" do
      allow(Process).to receive(:kill).and_call_original
      allow(Process).to receive(:kill).with(0, 999_999).and_raise(Errno::ESRCH)

      expect(described_class::PID_ALIVE.call(Process.pid)).to be(true)
      expect(described_class::PID_ALIVE.call(999_999)).to be(false)
    end

    it "treats a process owned by another user as alive" do
      allow(Process).to receive(:kill).with(0, 1).and_raise(Errno::EPERM)

      expect(described_class::PID_ALIVE.call(1)).to be(true)
    end
  end
end
