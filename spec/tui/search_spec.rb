# frozen_string_literal: true

require_relative "spec_helper"

# Fact 34: Search runs the existing query and shows collection, document and section.
RSpec.describe SFL::TUI::Search do
  let(:hit) do
    SFL::Core::Types::RetrievalResult.new(clause_id: "m1", text: "Method one.", section_id: "paper.md#method", rrf_score: 0.031)
  end
  let(:retriever) { instance_double(SFL::Store::PgHybridRetriever, retrieve: [hit]) }
  let(:services) { SFL::TUI::Services.null(source: TUISpecSupport.source, retriever:) }

  def press(state, *keys)
    keys.reduce([state, nil]) { |(current, _), key| described_class.update(current, TUISpecSupport.key(key), services) }
  end

  it "types a query after / and runs the retriever on enter" do
    typed, = press(described_class.initial, "/", "m", "e", "t", "backspace")
    done, command = press(typed, "enter")
    message = command.call

    expect(typed).to have_attributes(query: "me", editing: true)
    expect(done.editing).to be(false)
    expect(retriever).to have_received(:retrieve).with(SFL::Core::Types::RetrievalQuery.new(query: "me", limit: 20))
    expect(message.rows).to eq([
{
  collection: "papers",
  document_key: "paper.md",
  section: "Method",
  section_id: "paper.md#method",
  text: "Method one.",
  score: 0.031,
},
])
  end

  it "does not search for a blank query and stops typing on esc" do
    expect(press(described_class.initial, "/", "enter").last).to be_nil
    expect(press(described_class.initial, "/", "esc").first.editing).to be(false)
    expect(press(described_class.initial, "/", "tab").first.query).to eq("")
  end

  it "stores results and moves through them" do
    rows = [{ text: "a" }, { text: "b" }]
    state, = described_class.update(described_class.initial, SFL::TUI::Messages::SearchResults.new(query: "q", rows:), services)

    expect(press(state, "down", "down").first.cursor).to eq(1)
    expect(press(state, "up").first.cursor).to eq(0)
    expect(press(state, "x").first).to eq(state)
    expect(described_class.status(state)).to eq('2 results for "q"')
    expect(described_class.update(state, Object.new, services)).to eq([state, nil])
  end

  it "draws the query and the results with collection, document and section" do
    rows = [{ collection: "papers", document_key: "paper.md", section: "Method", text: "Method one.", score: 0.031 }]
    state = described_class.initial.with(query: "method", results: rows)
    lines = TUISpecSupport.render(width: 100, height: 8) { |frame, tui| described_class.render(state, frame, frame.area, tui) }

    expect(lines.join("\n")).to include("method", "papers", "paper.md", "Method", "0.031")
    expect(described_class.capturing?(state)).to be(false)
    expect(described_class.help(state)).to include("Enter search")
  end
end
