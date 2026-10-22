# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Dashboard::State do
  subject(:state) do
    described_class.initial(run_id: "run-1", kind: "ingest", collection: "papers", models: ["embedding ollama/x"],
      documents: 2, now: Time.at(0))
  end

  it "counts sections and closes a document when all its sections are done (fact 48)" do
    first = state.start(2).advance.advance
    second = first.start(3).advance(by: 1, failed: 1)

    expect([first.documents_done, first.documents_started]).to eq([1, 1])
    expect(second).to have_attributes(documents_done: 1, documents_started: 2, sections_done: 3, sections_total: 5,
      doc_done: 1, doc_total: 3, failures: 1)
  end

  it "ignores a start with no sections" do
    expect(state.start(0)).to eq(state)
  end

  it "adds clauses and defaulted counts and names the current item" do
    noted = state.note(clauses: 4, defaulted: 1).note(clauses: 2, defaulted: 0).item(:a)

    expect(noted).to have_attributes(clauses: 6, defaulted: 1, current_item: "a")
    expect(noted.item(nil).current_item).to be_nil
  end

  it "keeps the newest log lines and counts backoffs" do
    logged = (1..(described_class::LOG_LIMIT + 5)).reduce(state) { |acc, n| acc.add_log("line #{n}") }
    backed = logged.add_log("retry", backoff: true)

    expect(logged.log.size).to eq(described_class::LOG_LIMIT)
    expect(logged.log.first).to eq("line 6")
    expect(backed.backoffs).to eq(1)
  end

  it "computes elapsed time, rate and both ETAs from the clock" do
    running = state.start(4).advance.advance.tick(Time.at(60))

    expect(running.elapsed).to eq(60.0)
    expect(running.pace).to eq(30.0)
    expect(running.rate).to eq(2.0)
    expect(running.document_eta).to eq(60.0)
    # 4 sections over 1 of 2 expected documents: 8 expected, 6 left at 30 s each.
    expect(running.expected_sections).to eq(8)
    expect(running.run_eta).to eq(180.0)
  end

  it "has no ETA before a section finishes, and no negative elapsed time" do
    expect([state.pace, state.run_eta, state.document_eta]).to eq([nil, nil, nil])
    expect(state.tick(Time.at(-5)).elapsed).to eq(0.0)
    expect(state.rate).to eq(0.0)
  end

  it "uses the known section total when the document count is unknown or reached" do
    unknown = described_class.initial(run_id: "r", kind: "annotate", collection: nil, models: [], documents: nil, now: Time.at(0))

    expect(unknown.start(3).expected_sections).to eq(3)
    expect(state.start(1).start(1).expected_sections).to eq(2)
  end

  it "records stopping and the outcome" do
    expect(state.stop.stopping).to be(true)
    expect(state.finish(:interrupted).outcome).to eq("interrupted")
  end
end
