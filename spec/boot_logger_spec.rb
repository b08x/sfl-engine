# frozen_string_literal: true

require "spec_helper"
require "journald/logger"

RSpec.describe SFL::Boot, ".logger" do
  let(:socket) { File.join(Dir.mktmpdir, "journal.sock") }
  let(:opts) { { load_dotenv: false, journald_socket: socket } }

  before do
    allow(Journald::Logger).to receive(:new).and_return(instance_double(Journald::Logger, send_message: nil))
    allow(File).to receive(:socket?).and_call_original
    allow(File).to receive(:socket?).with(socket).and_return(true)
  end

  it "defaults to a stderr logger at INFO" do
    expect(described_class.logger(env: {}, **opts)).to be_a(SFL::Core::Ports::StderrLogger)
  end

  it "builds a journald logger for SFL_LOG_TARGET=journald" do
    logger = described_class.logger(env: { "SFL_LOG_TARGET" => "journald" }, **opts)

    expect(logger).to be_a(SFL::Core::Ports::JournaldLogger)
  end

  it "passes SFL_LOG_LEVEL through to the journald minimum priority" do
    described_class.logger(env: { "SFL_LOG_TARGET" => "journald", "SFL_LOG_LEVEL" => "debug" }, **opts)

    expect(Journald::Logger).to have_received(:new).with("sfl-engine", Journald::LOG_DEBUG, sfl_run_id: kind_of(String))
  end

  it "rejects an unknown target, naming the allowed values" do
    expect { described_class.logger(env: { "SFL_LOG_TARGET" => "syslog" }, **opts) }
      .to raise_error(SFL::Boot::Error, /SFL_LOG_TARGET.*stderr, journald/)
  end

  it "rejects an unknown level" do
    expect { described_class.logger(env: { "SFL_LOG_LEVEL" => "loud" }, **opts) }
      .to raise_error(SFL::Boot::Error, /SFL_LOG_LEVEL/)
  end

  it "returns a MultiLogger for a comma list, tolerating spaces" do
    logger = described_class.logger(env: { "SFL_LOG_TARGET" => "stderr, journald" }, **opts)

    expect(logger).to be_a(SFL::Core::Ports::MultiLogger)
  end

  it "rejects an unknown name inside a list" do
    expect { described_class.logger(env: { "SFL_LOG_TARGET" => "stderr,syslog" }, **opts) }
      .to raise_error(SFL::Boot::Error, /SFL_LOG_TARGET/)
  end

  it "raises Boot::Error naming the socket when journald is listed and the socket is missing" do
    missing = "/nonexistent/journal/socket"

    expect { described_class.logger(env: { "SFL_LOG_TARGET" => "stderr,journald" }, load_dotenv: false, journald_socket: missing) }
      .to raise_error(SFL::Boot::Error, /#{Regexp.escape(missing)}/)
  end

  it "does not check the socket when journald is not listed" do
    expect { described_class.logger(env: {}, load_dotenv: false, journald_socket: "/nonexistent") }.not_to raise_error
  end

  describe "run id" do
    it "generates a UUID when SFL_RUN_ID is unset or empty" do
      expect(described_class.run_id(env: {}, load_dotenv: false)).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
      expect(described_class.run_id(env: { "SFL_RUN_ID" => "" }, load_dotenv: false)).to match(/\A\h{8}-/)
    end

    it "honours SFL_RUN_ID when set" do
      expect(described_class.run_id(env: { "SFL_RUN_ID" => "abc" }, load_dotenv: false)).to eq("abc")
    end

    it "tags journald through the tags: argument" do
      described_class.logger(env: { "SFL_LOG_TARGET" => "journald", "SFL_RUN_ID" => "abc" }, **opts)

      expect(Journald::Logger).to have_received(:new).with("sfl-engine", Journald::LOG_INFO, sfl_run_id: "abc")
    end

    it "appends run_id= on stderr lines" do
      logger = described_class.logger(env: { "SFL_RUN_ID" => "abc" }, **opts)

      expect { logger.info("hello", n: 1) }.to output(/\[INFO\] hello n=1 run_id=abc$/).to_stderr_from_any_process
    end
  end
end
