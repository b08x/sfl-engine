# frozen_string_literal: true

require "tmpdir"
require_relative "export_helper"

# Facts 41, 44, 45: export file name and location, recorded as an export run.
RSpec.describe SFL::Export::Exporter do
  let(:run_log) { SFL::Core::Ports::Fake::RunLog.new }
  let(:time) { Time.new(2026, 10, 17, 9, 5, 3) }

  def exporter(dir) = described_class.new(source: TUISpecSupport.source, run_log:, dir:, clock: -> { time }, run_id: -> { "run-9" })

  it "writes <collection>-<timestamp>.jsonl under the output directory and records an export run" do
    Dir.mktmpdir do |root|
      dir = File.join(root, "exports")
      result = exporter(dir).call(ExportSpecSupport.papers_picks, :jsonl)

      expect(result).to eq(path: File.join(dir, "papers-20261017T090503.jsonl"), count: 6, run_id: "run-9")
      expect(File.read(result[:path])).to eq(ExportSpecSupport.golden("papers.jsonl"))
      expect(run_log.list.first).to include(run_id: "run-9", kind: "export", collection: "papers", total: 6, done: 6,
        status: "finished", pid: Process.pid, current_item: result[:path])
    end
  end

  it "writes Markdown with the md extension and names a multi-collection export mixed" do
    Dir.mktmpdir do |dir|
      state = TUISpecSupport.browse_state
      picks = state.with(selection: state.selection.select_all(state.tree, ["c:1", "c:2"])).picks

      expect(exporter(dir).call(picks, :markdown)[:path]).to end_with("mixed-20261017T090503.md")
    end
  end

  it "rejects an unknown format and marks a failed write's run failed" do
    Dir.mktmpdir do |dir|
      expect { exporter(dir).call([], :csv) }.to raise_error(ArgumentError, /unknown export format/)

      blocked = File.join(dir, "file")
      File.write(blocked, "")
      expect { exporter(File.join(blocked, "sub")).call(ExportSpecSupport.papers_picks, :jsonl) }.to raise_error(SystemCallError)
      expect(run_log.list.first).to include(status: "failed")
    end
  end

  it "names the unknown format in the error" do
    Dir.mktmpdir do |dir|
      expect { exporter(dir).call([], :csv) }.to raise_error(ArgumentError, "unknown export format: :csv")
    end
  end

  it "logs the written export with its path, clause count, format and run id" do
    Dir.mktmpdir do |dir|
      logger = instance_spy(SFL::Core::Ports::Logger)
      exporter = described_class.new(source: TUISpecSupport.source, run_log:, dir:, logger:, clock: -> { time }, run_id: -> { "run-9" })
      result = exporter.call(ExportSpecSupport.papers_picks, :markdown)

      expect(logger).to have_received(:info).with("export written", path: result[:path], clauses: 6, format: :markdown, run_id: "run-9")
    end
  end

  it "defaults to the current time and a random run id" do
    Dir.mktmpdir do |dir|
      result = described_class.new(source: TUISpecSupport.source, run_log:, dir:).call(ExportSpecSupport.papers_picks, :jsonl)

      expect(File.basename(result[:path])).to match(/\Apapers-\d{8}T\d{6}\.jsonl\z/)
      expect(result[:run_id]).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
      expect(described_class.new(source: TUISpecSupport.source, run_log:, dir:).call([], :jsonl)[:run_id]).not_to eq(result[:run_id])
    end
  end
end
