# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "tmpdir"

RSpec.describe SFL::Eval::UnseenRunner do
  let(:logger) { instance_double(SFL::Core::Ports::StderrLogger, info: nil, error: nil) }
  let(:out) { StringIO.new }
  let(:status) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:lines) { ["progress turn=1 total=2\n", "log noise\n", "progress turn=2 total=2\n"] }
  let(:calls) { [] }
  let(:process_runner) do
    lines_ = lines
    status_ = status
    calls_ = calls
    lambda do |env, args, &block|
      calls_ << [env, args]
      block.call(lines_)
      status_
    end
  end
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  def runner(run_id: -> { "rid-1" })
    described_class.new(logger:, process_runner:, run_id_factory: run_id, out:, clock: -> { 0.0 })
  end

  def run_item = runner.run_item(number: 11, input: "in.jsonl", out_dir: dir, command: ["x"])

  it "passes a distinct SFL_RUN_ID per item to the child env" do
    ids = %w[a b].each
    r = runner(run_id: -> { ids.next })
    r.run_item(number: 11, input: "i", out_dir: dir, command: ["x"])
    r.run_item(number: 12, input: "i", out_dir: dir, command: ["x"])

    expect(calls.map { |env, _| env["SFL_RUN_ID"] }).to eq(%w[a b])
  end

  it "counts turns from progress lines only and returns the count" do
    expect(run_item).to include(turns: 2, success: true)
  end

  it "logs start and finish with eval fields, run id, turns and duration" do
    run_item

    expect(logger).to have_received(:info).with("eval item started", eval_task: "run_unseen", eval_item: "nd-11", item_run_id: "rid-1")
    expect(logger).to have_received(:info).with("eval item finished", eval_task: "run_unseen", eval_item: "nd-11",
      item_run_id: "rid-1", turns: 2, duration_s: 0.0, exit_status: 0)
  end

  it "writes every child line to run.log and keeps terminal output lines" do
    run_item

    expect(File.read(File.join(dir, "run.log"))).to eq(lines.join)
    expect(out.string).to include("nd-11: finished, 2 turns, exit 0")
  end

  it "logs an error and reports failure on non-zero exit" do
    allow(status).to receive_messages(success?: false, exitstatus: 1)

    expect(run_item).to include(success: false)
    expect(logger).to have_received(:error).with("eval item failed", hash_including(eval_item: "nd-11", exit_status: 1))
  end
end
