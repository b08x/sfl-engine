# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::TimeoutBreaker do
  subject(:breaker) { described_class.new(timeout_seconds: 0.05) }

  it_behaves_like "a breaker port"

  it "raises Timeout::Error when the block exceeds the configured timeout" do
    expect { breaker.call("slow") { sleep 1 } }.to raise_error(Timeout::Error, /slow exceeded 0.05s timeout/)
  end

  it "does not time out a call that finishes within the budget" do
    expect(breaker.call("fast") { 42 }).to eq(42)
  end

  it "never times out when timeout_seconds is nil" do
    unbounded = described_class.new(timeout_seconds: nil)

    expect(unbounded.call("label") { 42 }).to eq(42)
  end

  it "never times out when timeout_seconds is zero" do
    disabled = described_class.new(timeout_seconds: 0)

    expect(disabled.call("label") { 42 }).to eq(42)
  end
end
