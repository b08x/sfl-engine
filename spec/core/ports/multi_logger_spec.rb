# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::MultiLogger do
  let(:first) { instance_double(SFL::Core::Ports::StderrLogger, info: nil, error: nil) }
  let(:second) { instance_double(SFL::Core::Ports::StderrLogger, info: nil, error: nil) }
  let(:logger) { described_class.new([first, second]) }

  it "is a Ports::Logger" do
    expect(logger).to be_a(SFL::Core::Ports::Logger)
  end

  it "forwards the message and fields to every child" do
    logger.info("done", count: 2)

    expect(first).to have_received(:info).with("done", count: 2)
    expect(second).to have_received(:info).with("done", count: 2)
  end

  it "forwards a block to every child" do
    seen = []
    capture = Class.new { define_method(:error) { |message = nil, **_fields, &block| seen << (message || block.call) } }
    described_class.new([capture.new, capture.new]).error { "boom" }

    expect(seen).to eq(%w[boom boom])
  end

  it "keeps calling later children when one raises, and reports on stderr" do
    allow(first).to receive(:info).and_raise(IOError, "socket gone")

    expect { logger.info("x", a: 1) }.to output(/MultiLogger.*IOError.*socket gone/).to_stderr
    expect(second).to have_received(:info).with("x", a: 1)
  end
end
