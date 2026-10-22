# frozen_string_literal: true

require "shellwords"
require "socket"
require "tmpdir"
require "spec_helper"

# Facts 66, 67, 69 and 71: the kitty adapter, its detection, the argv for a
# new tab and for an inline image. The runner is a fake: no spec drives kitty.
RSpec.describe SFL::Core::Ports::KittyHost do
  let(:runs) { [] }
  let(:runner) do
    calls = runs
    Class.new do
      define_method(:run) { |*argv| calls << argv }
    end.new
  end
  let(:host) { described_class.new(listen_on: "unix:/tmp/kitty-test", runner:) }

  it "is a TerminalHost (fact 66)" do
    expect(host).to be_a(SFL::Core::Ports::TerminalHost)
    expect(SFL::Core::Ports::Null::TerminalHost.new).to be_a(SFL::Core::Ports::TerminalHost)
  end

  describe ".detect (fact 67)" do
    let(:socket) { -> (path) { path == "/tmp/kitty-test" } }

    it "chooses kitty when KITTY_WINDOW_ID is set and the KITTY_LISTEN_ON socket exists" do
      chosen = described_class.detect(window_id: "20", listen_on: "unix:/tmp/kitty-test", socket_check: socket, runner:)

      expect(chosen).to be_a(described_class)
    end

    it "chooses the null host without KITTY_WINDOW_ID, without KITTY_LISTEN_ON, or when the socket is missing" do
      [
        { window_id: nil, listen_on: "unix:/tmp/kitty-test" },
        { window_id: "", listen_on: "unix:/tmp/kitty-test" },
        { window_id: "20", listen_on: nil },
        { window_id: "20", listen_on: "unix:/tmp/gone" },
      ].each do |env|
        expect(described_class.detect(**env, socket_check: socket)).to be_a(SFL::Core::Ports::Null::TerminalHost), env.inspect
      end
    end

    it "takes an abstract socket or a tcp address as reachable" do
      expect(described_class.reachable?("1", "unix:@kitty", socket)).to be(true)
      expect(described_class.reachable?("1", "tcp:localhost:5000", socket)).to be(true)
    end
  end

  # Fact 69 (checked by hand inside kitty as well).
  it "opens a new tab running the command in the working directory, held open after it exits" do
    opened = host.launch_tab(cmd: ["/repo/exe/sfl-analyze", "ingest", "--collection", "papers", "/data/papers"],
      cwd: "/repo", title: "sfl ingest papers", env: { "SFL_RUN_ID" => "run-1" })

    expect(opened).to be(true)
    expect(runs.map(&:shelljoin)).to eq([
      "kitten @ --to unix:/tmp/kitty-test launch --type\\=tab --tab-title sfl\\ ingest\\ papers --cwd /repo --hold " \
        "--env SFL_RUN_ID\\=run-1 -- /repo/exe/sfl-analyze ingest --collection papers /data/papers",
    ])
  end

  # Fact 71 (checked by hand inside kitty as well).
  it "shows an image with kitten icat in an overlay window" do
    expect(host.show_image("/data/figure.png")).to be(true)
    expect(runs.map(&:shelljoin)).to eq([
      "kitten @ --to unix:/tmp/kitty-test launch --type\\=overlay --title sfl\\ image -- kitten icat --hold -- /data/figure.png",
    ])
  end

  it "raises TerminalHost::Error when kitty fails or kitten is missing" do
    failing = Class.new { def run(*) = raise(Errno::ENOENT, "kitten") }.new

    expect { described_class.new(listen_on: "unix:/x", runner: failing).show_image("/a.png") }
      .to raise_error(SFL::Core::Ports::TerminalHost::Error, /kitty remote control failed/)
  end

  it "runs through tty-command by default" do
    expect(described_class.new(listen_on: "unix:/x").instance_variable_get(:@runner)).to be_a(TTY::Command)
  end

  # Under ".detect" so that mutant selects these examples for that method.
  describe ".detect defaults" do
    it "checks a unix socket on disk by default" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "kitty.sock")
        server = UNIXServer.new(path)

        expect(described_class.detect(window_id: "1", listen_on: "unix:#{path}")).to be_a(described_class)
        expect(described_class.detect(window_id: "1", listen_on: "unix:#{dir}/none")).to be_a(SFL::Core::Ports::Null::TerminalHost)
      ensure
        server&.close
      end
    end

    it "builds the host with the given runner and address" do
      chosen = described_class.detect(window_id: "1", listen_on: "tcp:localhost:5000", runner:)
      chosen.show_image("/a.png")

      expect(runs.first.first(4)).to eq(["kitten", "@", "--to", "tcp:localhost:5000"])
    end

    it "builds the host with the address and a quiet tty-command runner when no runner is given" do
      chosen = described_class.detect(window_id: "1", listen_on: "tcp:localhost:5000")

      expect(chosen.instance_variable_get(:@listen_on)).to eq("tcp:localhost:5000")
      expect(chosen.instance_variable_get(:@runner).printer).to be_a(TTY::Command::Printers::Null)
    end
  end

  describe "exact detection and error mapping" do
    def failing(message) = Class.new { define_method(:run) { |*| raise Class.new(Errno::EIO) { define_method(:message) { message } } } }.new

    it "treats a blank window id or address as unreachable" do
      expect(described_class.reachable?("  ", "tcp:x", -> (_) { true })).to be(false)
      expect(described_class.reachable?("1", "  ", -> (_) { true })).to be(false)
    end

    it "reports the stripped first line of the failure" do
      host = described_class.new(listen_on: "unix:/x", runner: failing("  no window matched  \nsecond line"))

      expect { host.show_image("/a.png") }
        .to raise_error(SFL::Core::Ports::TerminalHost::Error, "kitty remote control failed: no window matched")
    end

    it "reports an empty failure message as empty" do
      host = described_class.new(listen_on: "unix:/x", runner: failing(""))

      expect { host.show_image("/a.png") }.to raise_error(SFL::Core::Ports::TerminalHost::Error, "kitty remote control failed: ")
    end

    it "launches a tab without env vars and passes an image path as a string" do
      host.launch_tab(cmd: ["true"], cwd: "/", title: "t")
      host.show_image(Pathname.new("/data/x.png"))

      expect(runs.first).to eq(%w[kitten @ --to unix:/tmp/kitty-test launch --type=tab --tab-title t --cwd / --hold -- true])
      expect(runs.last.last).to eq("/data/x.png")
    end

    it "ends options before a command or image path that starts with a dash" do
      host.launch_tab(cmd: ["--help"], cwd: "/", title: "t")
      host.show_image("-x.png")

      expect(runs.first.last(2)).to eq(["--", "--help"])
      expect(runs.last.last(2)).to eq(["--", "-x.png"])
    end
  end
end
