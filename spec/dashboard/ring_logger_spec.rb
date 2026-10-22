# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Dashboard::RingLogger do
  subject(:logger) { described_class.new(board) }

  let(:board) do
    SFL::Dashboard::Board.new(SFL::Dashboard::State.initial(run_id: "r", kind: "ingest", collection: nil, models: [],
      documents: nil, now: Time.at(0)))
  end

  it "writes lines with their fields to the board, without the run id (fact 50)" do
    logger.info("section done", section_id: "a#1", run_id: "r")
    logger.error { "boom" }

    expect(board.state.log).to eq(["[INFO] section done section_id=a#1", "[ERROR] boom"])
  end

  it "drops lines below its level" do
    described_class.new(board, level: 2).info("quiet")

    expect(board.state.log).to be_empty
  end

  it "counts a 429 retry warning as a backoff and nothing else (fact 49)" do
    logger.warn("pass_two.annotate attempt failed, retrying", status: 429, attempt: 1)
    logger.warn("pass_two.annotate attempt failed, retrying", status: 503)
    logger.warn("pass_two.annotate attempt failed, retries exhausted", status: 429)

    expect(board.state.backoffs).to eq(1)
  end

  it "answers every severity" do
    %i[debug info warn error fatal].each { |severity| expect(logger.public_send(severity, "x")).to be_nil }
  end
end
