# frozen_string_literal: true

require_relative "../spec_helper"

# Fact 70: the fallback runs the ingest as a detached child with its output in a log file.
RSpec.describe SFL::TUI::Launcher::DetachedChild do
  it "spawns the command in its own process group with output appended to a log file, and detaches it" do
    spawned = []
    detached = []
    made = []
    child = described_class.new(
      log_dir: "/logs", cwd: "/repo",
      spawner: -> (*argv, **opts) { (spawned << [argv, opts]) && 4242 },
      detacher: -> (pid) { detached << pid },
      mkdir: -> (dir) { made << dir }
    )

    log = child.call(["/repo/exe/sfl-analyze", "ingest", "/data", "--collection", "papers"], env: { "SFL_RUN_ID" => "run-1" }, name: "ingest-run-1")

    expect(log).to eq("/logs/ingest-run-1.log")
    expect(made).to eq(["/logs"])
    expect(spawned.first).to eq(
      [
        [{ "SFL_RUN_ID" => "run-1" }, "/repo/exe/sfl-analyze", "ingest", "/data", "--collection", "papers"],
        { chdir: "/repo", in: File::NULL, out: ["/logs/ingest-run-1.log", "a"], err: %i[child out], pgroup: true },
      ]
    )
    expect(detached).to eq([4242])
  end

  it "expands a relative log directory against the current directory" do
    child = described_class.new(log_dir: "./output/logs", cwd: "/repo", spawner: -> (*, **) { 1 }, detacher: -> (_) {},
      mkdir: -> (_) {})

    expect(child.call(["true"], env: {}, name: "x")).to eq(File.join(Dir.pwd, "output/logs/x.log"))
  end
end
