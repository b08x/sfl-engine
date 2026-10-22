# frozen_string_literal: true

require_relative "spec_helper"

# Fact 68: the launcher takes a path, a collection (existing or new) and the ingest flags.
RSpec.describe SFL::TUI::Launcher do
  let(:state) { described_class.open(%w[papers notes]) }

  def type(state, text) = text.chars.reduce(state) { |acc, char| described_class.update(acc, char).first }

  def press(state, key) = described_class.update(state, key).first

  it "types into the path, collection and flags fields in turn" do
    filled = type(state, "/data/new")
    filled = type(press(filled, "tab"), "fresh")
    filled = type(press(filled, "tab"), "--disable-tracing")

    expect(filled).to have_attributes(path: "/data/new", collection: "fresh", flags: "--disable-tracing", field: 2)
    expect(press(filled, "backspace").flags).to eq("--disable-tracin")
    expect(press(filled, "shift_back_tab").field).to eq(1)
    expect(press(filled, "tab").field).to eq(0)
  end

  it "steps through existing collections with the arrows in the collection field" do
    collection = press(state, "tab")

    expect(press(collection, "down").collection).to eq("papers")
    expect(press(press(collection, "down"), "down").collection).to eq("notes")
    expect(press(press(collection, "down"), "down")).to be_existing
    expect(press(state, "down").field).to eq(1)
  end

  it "starts `sfl-analyze ingest PATH --collection NAME [flags]` on Enter and closes" do
    filled = type(press(press(type(state, "/data/papers"), "tab"), "down"), "")
    filled = type(press(filled, "tab"), "--output-dir out --disable-tracing")
    closed, request = described_class.update(filled, "enter")

    expect(closed).to be_nil
    expect(request.argv).to eq(
      [described_class::EXE, "ingest", "/data/papers", "--collection", "papers", "--output-dir", "out", "--disable-tracing"]
    )
    expect(described_class::EXE).to end_with("exe/sfl-analyze")
  end

  describe "Request#argv contract with SFL::CLI.parse" do
    def parsed(flags) = SFL::CLI.parse(described_class::Request.new(path: "/data/papers", collection: "papers", flags:).argv.drop(1))

    it "parses as an ingest of the path into the collection, with the flags" do
      result = parsed(["--output-dir", "x", "--disable-tracing"])

      expect(result).to include(command: :ingest, input: "/data/papers")
      expect(result[:options]).to include(collection: "papers", output_dir: "x", disable_tracing: true)
    end

    it "parses with no extra flags" do
      result = parsed([])

      expect(result).to include(command: :ingest, input: "/data/papers")
      expect(result[:options]).to include(collection: "papers", output_dir: SFL::CLI::DEFAULT_OUTPUT_DIR)
    end
  end

  it "defaults the collection to the path's base name, as the CLI does" do
    expect(described_class.request(type(state, "/data/talks/")).collection).to eq("talks")
  end

  it "refuses a missing path, unknown flags, a stray argument and --collection among the flags" do
    flagged = -> (flags) { type(press(press(type(state, "/d"), "tab"), "tab"), flags) }

    expect(press(state, "enter").error).to eq("path is required")
    expect(press(flagged.call("--bogus"), "enter").error).to include("invalid option: --bogus")
    expect(press(flagged.call("extra"), "enter").error).to eq("not an ingest flag: extra")
    expect(press(flagged.call("--collection x"), "enter").error).to eq("set the collection in its own field")
    expect(press(flagged.call("'open"), "enter").error).to start_with("flags:")
  end

  describe "exact transitions" do
    let(:errored) { state.with(error: "path is required") }

    it "returns the next state and no request for every non-submitting key, clearing the error" do
      expect(described_class.update(errored, "x")).to eq([state.with(path: "x"), nil])
      expect(described_class.update(errored.with(path: "ab"), "backspace")).to eq([state.with(path: "a"), nil])
      expect(described_class.update(errored, "tab")).to eq([state.with(field: 1), nil])
      expect(described_class.update(errored, "back_tab")).to eq([state.with(field: 2), nil])
      expect(described_class.update(errored, "shift_back_tab")).to eq([state.with(field: 2), nil])
      expect(described_class.update(errored, "up")).to eq([state.with(field: 2), nil])
      expect(described_class.update(errored, "down")).to eq([state.with(field: 1), nil])
    end

    it "keeps the refused state with its error and no request" do
      expect(described_class.update(state, "enter")).to eq([state.with(error: "path is required"), nil])
    end

    it "clears the error when an arrow picks a collection" do
      collection = errored.with(field: 1)

      expect(described_class.update(collection, "down")).to eq([collection.with(collection: "papers", error: nil), nil])
    end

    it "moves between fields with the arrows in the collection field when there are no collections" do
      empty = described_class.open([]).with(field: 1)

      expect(press(empty, "down")).to have_attributes(field: 2, collection: "")
      expect(press(empty, "up")).to have_attributes(field: 0, collection: "")
    end

    it "steps from the current collection, ignoring its case and surrounding spaces, and wraps" do
      three = described_class.open(%w[papers notes talks]).with(field: 1)

      expect(press(three.with(collection: " Notes "), "down").collection).to eq("talks")
      expect(press(three.with(collection: " Notes "), "up").collection).to eq("papers")
      expect(press(three.with(collection: "talks"), "down").collection).to eq("papers")
      expect(press(three.with(collection: "papers"), "up").collection).to eq("talks")
      expect(press(three.with(collection: "new"), "up").collection).to eq("papers")
    end

    it "steps one collection at a time among five" do
      five = described_class.open(%w[a b c d e]).with(field: 1, collection: "c")

      expect(press(five, "up").collection).to eq("b")
      expect(press(five, "down").collection).to eq("d")
    end

    it "strips the path and the collection, and expands a relative path" do
      request = described_class.request(state.with(path: "  /data/x  ", collection: "  fresh  "))
      relative = described_class.request(state.with(path: "rel/dir", collection: "   "))

      expect(request).to have_attributes(path: "/data/x", collection: "fresh", flags: [])
      expect(relative.path).to eq(File.expand_path("rel/dir"))
      expect(relative.collection).to eq("dir")
    end

    it "refuses a path of only spaces" do
      expect(described_class.request(state.with(path: "   "))).to eq("path is required")
    end
  end

  it "closes on Esc and ignores other named keys" do
    expect(described_class.update(state, "esc")).to eq([nil, nil])
    expect(press(state, "f5")).to eq(state)
  end
end
