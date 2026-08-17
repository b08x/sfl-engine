# frozen_string_literal: true

require "spec_helper"
require "journald/logger"

RSpec.describe SFL::Core::Ports::JournaldLogger do
  subject(:logger) { described_class.new(progname: "test.component") }

  let(:mock_journald) { instance_double(Journald::Logger) }

  before do
    allow(Journald::Logger).to receive(:new).and_return(mock_journald)
    allow(mock_journald).to receive(:log_debug)
    allow(mock_journald).to receive(:log_info)
    allow(mock_journald).to receive(:log_warning)
    allow(mock_journald).to receive(:log_err)
    allow(mock_journald).to receive(:log_crit)
  end

  it_behaves_like "a logger port"

  it "delegates info to log_info" do
    logger.info("hello world")
    expect(mock_journald).to have_received(:log_info).with("hello world")
  end

  it "supports the block form, evaluated lazily" do
    computed = false
    logger.info { computed = true; "block message" }

    expect(computed).to be(true)
    expect(mock_journald).to have_received(:log_info).with("block message")
  end
end
