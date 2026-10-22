# frozen_string_literal: true

require "spec_helper"
require "ratatui_ruby"

module TUISpecSupport
  # Two collections. "papers" holds a markdown document with nested
  # headings and a transcript with two speaker turns; "notes" holds one
  # flat document.
  def self.collections
    [
      { id: 1, name: "papers", documents: [paper, talk] },
      { id: 2, name: "notes", documents: [note] },
    ]
  end

  def self.paper
    sections = [
      section("paper.md#intro", "Intro", 1, "heading", 2, children: [
        section("paper.md#background", "Background", 2, "heading", 1),
      ]),
      section("paper.md#method", "Method", 3, "heading", 1),
    ]
    { id: 10, document_key: "paper.md", title: "Paper", source_path: "/data/paper.md", sections: }
  end

  def self.talk
    sections = [section("talk.srt#turn-1", "Alice", 1, "turn", 1), section("talk.srt#turn-2", "Bob", 2, "turn", 1)]
    { id: 11, document_key: "talk.srt", title: nil, source_path: "/data/talk.srt", sections: }
  end

  def self.note
    { id: 20, document_key: "note.txt", title: "Note", source_path: "/data/note.txt", sections: [section("note.txt#0", nil, 1, "block", 0)] }
  end

  def self.section(section_id, label, ordinal, kind, clause_count, children: [])
    { section_id:, label:, ordinal:, kind:, level: nil, clause_count:, children: }
  end

  def self.clause(id, text)
    { id:, text:, ideational: { process_type: "material" }, interpersonal: { mood: "declarative", tenor: 0.5 } }
  end

  def self.clauses
    {
      "paper.md#intro" => [clause("i1", "Intro one."), clause("i2", "Intro two.")],
      "paper.md#background" => [clause("b1", "Background one.")],
      "paper.md#method" => [clause("m1", "Method one.")],
      "talk.srt#turn-1" => [clause("t1", "Hello there.")],
      "talk.srt#turn-2" => [clause("t2", "Hi Alice.")],
    }
  end

  def self.content_reviews
    [
      {
        id: "r1",
        section_id: "paper.md#method",
        modality: "image",
        source_file: "/data/figure.png",
        generated_text: "A chart of results.",
        reason: "image",
        status: "pending",
      },
      {
        id: "r2",
        section_id: "talk.srt#turn-1",
        modality: "audio",
        source_file: "/data/talk.wav",
        generated_text: "Hello there.",
        reason: "audio_transcript",
        status: "rejected",
      },
    ]
  end

  def self.annotation_reviews = { "b1" => { status: "pending", confidence: 0.42 }, "t2" => { status: "accepted", confidence: nil } }

  def self.source(**overrides)
    SFL::Core::Ports::Fake::BrowseSource.new(
      collections:, clauses:, content_reviews:, annotation_reviews:, **overrides
    )
  end

  def self.tree = SFL::TUI::Browse::Tree.load(source)

  def self.reviews = SFL::TUI::Browse::Reviews.new(content: content_reviews, annotations: annotation_reviews)

  # A Browse state with everything loaded and every node expanded.
  def self.browse_state(**changes)
    tree = clauses.reduce(self.tree) { |acc, (section_id, rows)| acc.with_clauses(section_id, rows) }
    expanded = Set.new(tree.roots + tree.roots.flat_map { |id| tree.descendants(id) })
    SFL::TUI::Browse::State.initial.with(tree:, reviews:, expanded:, **changes)
  end

  # @return [Integer] the tree row index of a node id
  def self.row_of(state, id) = state.rows.index { |node| node.id == id }

  def self.key(name) = SFL::TUI::Messages::Key.new(name)

  # Renders into ratatui's in-memory test terminal and returns its lines.
  # (RatatuiRuby::TestHelper needs minitest/mock, which this bundle lacks.)
  def self.render(width: 120, height: 30)
    RatatuiRuby.init_test_terminal(width, height)
    tui = RatatuiRuby::TUI.new
    RatatuiRuby.draw { |frame| yield frame, tui }
    RatatuiRuby.get_buffer_content.split("\n")
  ensure
    RatatuiRuby.restore_terminal
  end
end
