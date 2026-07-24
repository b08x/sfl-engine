# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe SFL::Core::Ports::StandardLogger do
  subject(:logger) { described_class.new(io:, progname: "test.component") }

  let(:io) { StringIO.new }

  it_behaves_like "a logger port"

  it "writes the message, severity, and progname to the given IO" do
    logger.info("hello world")

    expect(io.string).to include("INFO")
    expect(io.string).to include("test.component: hello world")
  end

  it "supports the block form, evaluated lazily" do
    computed = false
    logger.info { computed = true; "block message" }

    expect(computed).to be(true)
    expect(io.string).to include("block message")
  end

  it "suppresses messages below the configured level" do
    quiet = described_class.new(io:, level: Logger::WARN)
    quiet.debug("should not appear")
    quiet.info("should not appear either")
    quiet.warn("should appear")

    expect(io.string).not_to include("should not appear")
    expect(io.string).to include("should appear")
  end

  it "defaults to INFO level, so debug is suppressed but info is not" do
    default_logger = described_class.new(io:)
    default_logger.debug("quiet")
    default_logger.info("loud")

    expect(io.string).not_to include("quiet")
    expect(io.string).to include("loud")
  end
end
