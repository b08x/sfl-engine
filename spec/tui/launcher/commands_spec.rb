# frozen_string_literal: true

require "tmpdir"
require_relative "../spec_helper"

RSpec.describe SFL::TUI::Launcher::Commands do
  let(:dir) { Dir.mktmpdir }
  let(:request) { SFL::TUI::Launcher::Request.new(path: dir, collection: "papers", flags: []) }
  let(:spawned) { [] }
  let(:spawner) { -> (argv, env:, name:) { (spawned << [argv, env, name]) && "/logs/#{name}.log" } }
  let(:run_log) { SFL::Core::Ports::Fake::RunLog.new }

  def services(host) = SFL::TUI::Services.null(terminal_host: host, spawner:, run_log:, run_id: -> { "run-1" })

  after { FileUtils.remove_entry(dir) }

  # Fact 69 (and a manual check inside kitty).
  it "opens a new terminal tab running the ingest under the run id when the host can" do
    host = SFL::Core::Ports::Fake::TerminalHost.new
    message = described_class.start(services(host), request).call

    expect(host.tabs).to eq([
{
  cmd: request.argv,
  cwd: SFL::TUI::Launcher::ROOT,
  title: "sfl ingest papers",
  env: { "SFL_RUN_ID" => "run-1" },
},
])
    expect(spawned).to be_empty
    expect(message).to eq(SFL::TUI::Messages::Launched.new(text: "ingest papers started in a new tab as run run-1", detached: false))
  end

  # Fact 70: outside kitty, a detached child whose run the Runs tab shows.
  it "starts a detached child under the run id when the host cannot open tabs, and the Runs tab lists its run" do
    message = described_class.start(services(SFL::Core::Ports::Null::TerminalHost.new), request).call

    expect(spawned).to eq([[request.argv, { "SFL_RUN_ID" => "run-1" }, "ingest-run-1"]])
    expect(message.detached).to be(true)
    expect(message.text).to include("run-1", "/logs/ingest-run-1.log")

    # The child's CLI records its run under the SFL_RUN_ID it was given.
    run_id = SFL::Boot.run_id(env: spawned.first[1], load_dotenv: false)
    SFL::CLI::PgRunProgressSink.new(run_log:, run_id:, kind: "ingest", heartbeat_every: nil, collection: "papers").start(3)
    runs = SFL::TUI::Runs.load(services(nil)).call

    expect(runs.rows.map { |row| row[:run_id] }).to eq(["run-1"])
  end

  it "falls back to a detached child when kitty fails, logging a warning" do
    logger = instance_spy(SFL::Core::Ports::Logger)
    host = SFL::Core::Ports::Fake::TerminalHost.new(error: "kitty remote control failed: refused")
    message = described_class.start(services(host).with(logger:), request).call

    expect(message.detached).to be(true)
    expect(logger).to have_received(:warn).with("terminal tab failed, starting a detached ingest",
      error: "kitty remote control failed: refused")
  end

  it "refuses a path that does not exist" do
    message = described_class.start(services(SFL::Core::Ports::Null::TerminalHost.new),
      request.with(path: File.join(dir, "missing"))).call

    expect(message).to be_a(SFL::TUI::Messages::Failed)
    expect(message.detail).to start_with("no such path:")
    expect(spawned).to be_empty
  end
end
