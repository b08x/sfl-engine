# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::TimingInstrumenter do
  subject(:instrumenter) { described_class.new(clock:) }

  # Each `instrument` call consumes two clock reads (started_at + the ensure
  # block's elapsed measurement), so the clock must be able to tick more than
  # once per span — a finite `Array#shift` runs dry and returns nil, which
  # makes `monotonic - started_at` raise. Generate ticks lazily instead.
  let(:clock) do
    Class.new do
      def initialize
        @tick = 0.0
      end

      def clock_gettime(*)
        value = @tick
        @tick += 0.001
        value
      end
    end.new
  end

  it "reports clause, batch, provider, retry, and parse dimensions" do
    instrumenter.instrument("pass_two.batch", clause_count: 1, batch_id: "b-1") { nil }
    instrumenter.instrument("pass_two.provider_request", provider: "fake", batch_id: "b-1") { nil }
    instrumenter.instrument("pass_two.retry", attempt: 1) { nil }
    instrumenter.instrument("pass_two.parse.deserialization") { nil }
    instrumenter.instrument("pass_two.parse.normalization") { nil }
    instrumenter.instrument("pass_two.parse.classification") { nil }
    instrumenter.instrument("pass_two.clause", clause_id: "c-1", batch_id: "b-1") { nil }

    report = instrumenter.report

    expect(report[:clauses]).not_to be_empty
    expect(report[:batches].first).to include(idle_ms: be >= 0)
    expect(report[:provider_requests].first[:provider]).to eq("fake")
    expect(report[:retries][:attempts]).to eq(1)
    expect(report[:parsing].map { |span| span[:name] }).to include("pass_two.parse.classification")
  end
end
