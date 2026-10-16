# frozen_string_literal: true

require "spec_helper"
require "journald/logger"

RSpec.describe SFL::Boot, ".logger" do
  before { allow(Journald::Logger).to receive(:new).and_return(instance_double(Journald::Logger, send_message: nil)) }

  it "defaults to a stderr logger at INFO" do
    expect(described_class.logger(env: {}, load_dotenv: false)).to be_a(SFL::Core::Ports::StderrLogger)
  end

  it "builds a journald logger for SFL_LOG_TARGET=journald" do
    logger = described_class.logger(env: { "SFL_LOG_TARGET" => "journald" }, load_dotenv: false)

    expect(logger).to be_a(SFL::Core::Ports::JournaldLogger)
  end

  it "passes SFL_LOG_LEVEL through to the journald minimum priority" do
    described_class.logger(env: { "SFL_LOG_TARGET" => "journald", "SFL_LOG_LEVEL" => "debug" }, load_dotenv: false)

    expect(Journald::Logger).to have_received(:new).with("sfl-engine", Journald::LOG_DEBUG)
  end

  it "rejects an unknown target, naming the allowed values" do
    expect { described_class.logger(env: { "SFL_LOG_TARGET" => "syslog" }, load_dotenv: false) }
      .to raise_error(SFL::Boot::Error, /SFL_LOG_TARGET.*stderr, journald/)
  end

  it "rejects an unknown level" do
    expect { described_class.logger(env: { "SFL_LOG_LEVEL" => "loud" }, load_dotenv: false) }
      .to raise_error(SFL::Boot::Error, /SFL_LOG_LEVEL/)
  end
end
