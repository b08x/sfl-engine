# frozen_string_literal: true

require "spec_helper"
require "journald/logger"

RSpec.describe SFL::Core::Ports::JournaldLogger do
  subject(:logger) { described_class.new(progname: "test.component") }

  let(:mock_journald) { instance_double(Journald::Logger, send_message: nil) }

  before { allow(Journald::Logger).to receive(:new).and_return(mock_journald) }

  it_behaves_like "a logger port"

  it "emits MESSAGE, PRIORITY and the caller's code location as journald fields" do
    logger.info("hello world")

    expect(mock_journald).to have_received(:send_message).with(
      hash_including(priority: Journald::LOG_INFO, message: "hello world",
        code_file: __FILE__, code_line: a_kind_of(Integer), code_func: a_kind_of(String))
    )
  end

  it "maps each severity to its syslog priority" do
    { debug: 7, info: 6, warn: 4, error: 3, fatal: 2 }.each do |level, priority|
      logger.public_send(level, "m")
      expect(mock_journald).to have_received(:send_message).with(hash_including(priority:, message: "m"))
    end
  end

  it "passes structured fields through alongside the message" do
    logger.warn("retry succeeded", document_id: "doc-1", attempt: 2)

    expect(mock_journald).to have_received(:send_message)
      .with(hash_including(priority: 4, document_id: "doc-1", attempt: 2))
  end

  it "does not let a field override the reserved keys" do
    logger.info("real", message: "spoofed", priority: 0)

    expect(mock_journald).to have_received(:send_message).with(hash_including(priority: 6, message: "real"))
  end

  it "supports the block form, evaluated lazily" do
    computed = false
    logger.info { computed = true; "block message" }

    expect(computed).to be(true)
    expect(mock_journald).to have_received(:send_message).with(hash_including(message: "block message"))
  end

  it "emits nothing when there is no message" do
    logger.info

    expect(mock_journald).not_to have_received(:send_message)
  end
end
