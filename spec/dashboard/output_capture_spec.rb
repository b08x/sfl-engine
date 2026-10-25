# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Dashboard::OutputCapture do
  subject(:io) { described_class.new(board) }

  let(:board) do
    SFL::Dashboard::Board.new(SFL::Dashboard::State.initial(run_id: "r", kind: "ingest", collection: nil, models: [],
      documents: nil, now: Time.at(0)))
  end

  it "turns puts, print, printf, << and warn-style writes into log lines" do
    io.puts("one", ["two"])
    io.print("thr")
    io.print("ee\n")
    io.printf("%d\n", 4)
    io << "five\n"
    expect(io.write("six\n", "seven\n")).to eq(10)
    io.puts

    expect(board.state.log).to eq(%w[one two three 4 five six seven])
  end

  it "keeps a partial line until its newline arrives" do
    io.write("half")

    expect(board.state.log).to be_empty
  end

  it "behaves as a non-terminal IO" do
    io.sync = true

    expect([io.tty?, io.isatty, io.sync, io.fileno, io.flush]).to eq([false, false, true, nil, io])
  end

  it "is accepted by Logger as an IO device, not a filename" do
    logger = Logger.new(io)
    logger.info("from logger")

    expect(board.state.log.last).to include("from logger")
  end

  it "ignores close, so a Logger closing its device leaves the capture writable" do
    expect(io.close).to be_nil
    io.puts("after close")

    expect(board.state.log).to eq(["after close"])
  end

  it "drops a line written from a trap handler, which cannot take the board's lock" do
    allow(board).to receive(:update).and_raise(ThreadError)

    expect { io.puts("from trap") }.not_to raise_error
  end
end
