# frozen_string_literal: true

require "spec_helper"
require_relative "../tui/spec_helper"

RSpec.describe SFL::Dashboard::View do
  let(:state) do
    SFL::Dashboard::State.initial(run_id: "run-42", kind: "ingest", collection: "papers",
      models: ["pass_two_annotation openrouter/m1", "embedding ollama/e1"], documents: 3, now: Time.at(0))
      .start(4).item("talk.srt").advance.advance.note(clauses: 7, defaulted: 2)
      .add_log("[WARN] first line").add_log("[INFO] last line").tick(Time.at(125))
  end

  def screen(state, height: 30) = TUISpecSupport.render(width: 120, height:) { |frame, tui| described_class.render(state, frame, tui) }.join("\n")

  it "shows the run id, collection, models per task and elapsed time in the header (fact 47)" do
    text = screen(state)

    expect(text).to include("run run-42", "collection papers", "elapsed 02:05")
    expect(text).to include("pass_two_annotation openrouter/m1", "embedding ollama/e1")
  end

  it "has an ingest panel with documents, sections, clauses, rate, ETA and failures (fact 48)" do
    text = screen(state.advance(by: 1, failed: 1))

    expect(text).to include("Ingest", "documents 0/3", "sections 3/4", "clauses written 7", "rate 1.4 sections/min",
      "failures 1", "current talk.srt")
    expect(text).to match(/ETA \d\d:\d\d/)
  end

  it "has an annotation panel with turns, defaulted count, 429 backoffs and ETA (fact 49)" do
    text = screen(state.add_log("[WARN] retrying", backoff: true))

    expect(text).to include("Annotation", "turns 2/4 in this document", "defaulted 2", "429 backoffs 1", "ETA 02:05")
  end

  it "shows the last log lines and the Ctrl-C hint (fact 50)" do
    text = screen(state)

    expect(text).to include("Log", "[WARN] first line", "[INFO] last line", "Ctrl-C stop gracefully")
  end

  it "shows only the newest lines that fit" do
    many = (1..40).reduce(state) { |acc, n| acc.add_log("entry #{n}") }

    text = screen(many, height: 24)

    expect(text).to include("entry 40")
    expect(text).not_to match(/entry 1\s*│/)
  end

  it "shows the stopping hint, then the outcome on the final screen (fact 51)" do
    expect(screen(state.stop)).to include("sfl ingest · stopping", "Ctrl-C again to quit now")
    expect(screen(state.stop.finish("interrupted"))).to include("sfl ingest · interrupted", "interrupted · press any key to exit")
  end

  it "formats durations and ratios" do
    expect(described_class.duration(nil)).to eq("-")
    expect(described_class.duration(3723)).to eq("1:02:03")
    expect(described_class.duration(59.6)).to eq("01:00")
    expect(described_class.ratio(1, 0)).to eq(0.0)
    expect(described_class.ratio(3, 2)).to eq(1.0)
  end

  it "falls back to dashes and started documents when nothing is known" do
    bare = SFL::Dashboard::State.initial(run_id: "r", kind: "annotate", collection: nil, models: [], documents: nil,
      now: Time.at(0))

    expect(screen(bare)).to include("collection -", "models: -", "documents 0/0", "current -", "ETA -")
  end
end
