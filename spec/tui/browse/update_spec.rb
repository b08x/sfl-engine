# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe SFL::TUI::Browse::Update do
  let(:source) { TUISpecSupport.source }
  let(:services) { SFL::TUI::Services.null(source:, reviewer: "ana") }
  let(:state) { TUISpecSupport.browse_state }

  def press(state, *keys)
    keys.reduce([state, nil]) { |(current, _), key| described_class.call(current, TUISpecSupport.key(key), services) }
  end

  def at(state, id) = state.with(cursor: TUISpecSupport.row_of(state, id))

  it "moves the cursor and loads the clauses of a section the first time it is focused" do
    bare = SFL::TUI::Browse::State.initial.with(tree: TUISpecSupport.tree, expanded: Set["c:1", "d:10"])
    moved, command = press(bare, "down", "down")

    expect(moved.focused_row.id).to eq("s:paper.md#intro")
    expect(command.call).to eq(SFL::TUI::Messages::ClausesLoaded.new(section_id: "paper.md#intro",
      clauses: source.clauses("paper.md#intro")))
  end

  it "clamps the cursor at both ends" do
    expect(press(state, "up").first.cursor).to eq(0)
    expect(press(state.with(cursor: state.rows.size - 1), "down").first.cursor).to eq(state.rows.size - 1)
  end

  it "toggles expansion with enter" do
    collapsed, = press(state, "enter")

    expect(collapsed.expanded).not_to include("c:1")
    expect(press(collapsed, "enter").first.expanded).to include("c:1")
  end

  # Fact 38: Space toggles the focused row at any level.
  it "toggles selection of the focused tree row and of the focused clause" do
    selected, = press(at(state, "d:11"), " ")
    clause, = press(at(state, "s:paper.md#intro"), "tab", "down", " ")

    expect(selected.selection.state(state.tree, "d:11")).to eq(:full)
    expect(clause.selection.ids.to_a).to eq(["k:i2"])
    expect(press(selected, " ").first.selection).to be_empty
  end

  # Fact 40: a selects the level in view, Esc clears.
  it "selects every row at the current level with a and clears with esc" do
    all_documents, = press(at(state, "d:10"), "a")

    expect(%w[d:10 d:11 d:20].map { |id| all_documents.selection.state(state.tree, id) }).to all(eq(:full))
    expect(press(all_documents, "esc").first.selection).to be_empty
  end

  it "cycles the status filter with f" do
    expect(press(state, "f").first.filter).to eq("pending")
  end

  # Fact 41: e asks for a format, then exports.
  it "opens the export format choice only when something is selected and exports on j or m" do
    expect(press(state, "e").first.overlay).to be_nil

    exporter = instance_double(SFL::Export::Exporter, call: { path: "/out/papers-1.jsonl", count: 2 })
    services_with_exporter = services.with(exporter:)
    chosen, = press(at(state, "s:paper.md#intro"), " ", "e")
    closed, command = described_class.call(chosen, TUISpecSupport.key("j"), services_with_exporter)

    expect(chosen.overlay).to eq(:export)
    expect(closed.overlay).to be_nil
    expect(command.call).to eq(SFL::TUI::Messages::Exported.new(path: "/out/papers-1.jsonl", count: 2))
    expect(exporter).to have_received(:call).with(chosen.picks, :jsonl)
  end

  it "closes the format choice with esc and ignores other keys while it is open" do
    open = state.with(overlay: :export)

    expect(press(open, "x").first.overlay).to eq(:export)
    expect(press(open, "esc").first).to have_attributes(overlay: nil)
  end

  # Fact 30: approve and reject act on a pending content-review item.
  it "returns a decision command for A and R on a section with a pending review item" do
    review_queue = instance_spy(SFL::Store::PgReviewQueueRepository)
    reviewing = services.with(review_queue:)
    _, approve = described_class.call(at(state, "s:paper.md#method"), TUISpecSupport.key("A"), reviewing)
    _, reject = described_class.call(at(state, "s:paper.md#method"), TUISpecSupport.key("R"), reviewing)

    approve.call
    reject.call

    expect(review_queue).to have_received(:decide).with(id: "r1", decision: "approve", reviewer: "ana")
    expect(review_queue).to have_received(:decide).with(id: "r1", decision: "reject", reviewer: "ana")
  end

  it "ignores review keys on a section whose item is already decided, and on rows without one" do
    expect(press(at(state, "s:talk.srt#turn-1"), "A").last).to be_nil
    expect(press(at(state, "d:10"), "A").last).to be_nil
  end

  # Fact 32: the open-viewer key opens an image item's source file.
  it "opens an image item with o, and does nothing for other modalities" do
    opener = SFL::Core::Ports::Fake::Opener.new
    _, command = described_class.call(at(state, "s:paper.md#method"), TUISpecSupport.key("o"), services.with(opener:))
    command.call

    expect(opener.opened).to eq(["/data/figure.png"])
    expect(press(at(state, "s:talk.srt#turn-1"), "o").last).to be_nil
  end

  it "returns an edit command for E" do
    review_queue = instance_spy(SFL::Store::PgReviewQueueRepository)
    _, command = described_class.call(at(state, "s:paper.md#method"), TUISpecSupport.key("E"), services.with(review_queue:))

    expect(command.call).to be_a(SFL::TUI::Messages::Reviewed)
    expect(review_queue).to have_received(:decide).with(id: "r1", decision: "edit", reviewer: "ana")
  end

  it "reloads after a review and keeps still-present selections when the load arrives" do
    selected = state.selection.select(state.tree, "s:paper.md#method")
    _, command = described_class.call(state, SFL::TUI::Messages::Reviewed.new("ok"), services)
    loaded = command.call
    next_state, = described_class.call(state.with(selection: selected), loaded, services)

    expect(loaded).to be_a(SFL::TUI::Messages::BrowseLoaded)
    expect(next_state.selection.ids).to include("s:paper.md#method")
  end

  it "reloads the tree with r" do
    _, command = press(state, "r")

    expect(command.call).to be_a(SFL::TUI::Messages::BrowseLoaded)
  end

  it "ignores an unbound key on a section with a review item" do
    focused = at(state, "s:paper.md#method")

    expect(press(focused, "z")).to eq([focused, nil])
  end

  it "attaches loaded clauses and ignores clauses for an unknown section" do
    bare = SFL::TUI::Browse::State.initial.with(tree: TUISpecSupport.tree)
    message = SFL::TUI::Messages::ClausesLoaded.new(section_id: "paper.md#method", clauses: source.clauses("paper.md#method"))

    expect(described_class.call(bare, message, services).first.tree.loaded?("s:paper.md#method")).to be(true)
    unknown = message.with(section_id: "nope")
    expect(described_class.call(bare, unknown, services).first).to eq(bare)
  end

  describe "exact transitions" do
    let(:bare) { SFL::TUI::Browse::State.initial.with(tree: TUISpecSupport.tree) }

    def loaded_message(tree = TUISpecSupport.tree) = SFL::TUI::Messages::BrowseLoaded.new(tree:, reviews: TUISpecSupport.reviews)

    it "maps every bound key to its transition" do
      expect(described_class::KEY_ACTIONS).to eq(
        "up" => :cursor_up, "k" => :cursor_up, "down" => :cursor_down, "j" => :cursor_down,
        "tab" => :switch_focus, "enter" => :expand, "right" => :expand, "l" => :expand,
        " " => :select_focused, "a" => :select_all, "esc" => :clear_selection, "f" => :next_filter,
        "e" => :open_export, "r" => :reload
      )
      expect(described_class::KEY_ACTIONS).to be_frozen
    end

    it "returns the state and no command for a message it does not handle" do
      expect(described_class.call(state, SFL::TUI::Messages::Key, services)).to eq([state, nil])
      expect(described_class.call(state, Object.new, services)).to eq([state, nil])
    end

    it "keeps the state and reloads after a review" do
      next_state, command = described_class.call(state, SFL::TUI::Messages::Reviewed.new("ok"), services)

      expect(next_state).to equal(state)
      expect(command.call).to be_a(SFL::TUI::Messages::BrowseLoaded)
    end

    it "moves the tree cursor with up, k, down and j, resetting the clause cursor" do
      start = at(state, "s:paper.md#background").with(clause_cursor: 1)

      %w[up k].each { |key| expect(press(start, key)).to eq([start.with(cursor: 2, clause_cursor: 0), nil]) }
      %w[down j].each { |key| expect(press(start, key)).to eq([start.with(cursor: 4, clause_cursor: 0), nil]) }
    end

    it "keeps the cursor at 0 when the tree is empty" do
      empty = SFL::TUI::Browse::State.initial

      expect(press(empty, "down")).to eq([empty, nil])
      expect(press(empty, "up")).to eq([empty, nil])
    end

    it "moves and clamps the clause cursor while the clause pane has focus, without a command" do
      clauses = at(state, "s:paper.md#intro").with(focus: :clauses)

      expect(press(clauses, "down")).to eq([clauses.with(clause_cursor: 1), nil])
      expect(press(clauses.with(clause_cursor: 1), "down")).to eq([clauses.with(clause_cursor: 1), nil])
      expect(press(clauses.with(clause_cursor: 1), "up")).to eq([clauses, nil])
      expect(press(clauses, "up")).to eq([clauses, nil])
      expect(press(at(state, "d:10").with(focus: :clauses, clause_cursor: 3), "down"))
        .to eq([at(state, "d:10").with(focus: :clauses, clause_cursor: 0), nil])
    end

    it "loads clauses only for a focused section whose clauses are not loaded" do
      bare_expanded = bare.with(expanded: Set["c:1", "d:10"])

      expect(press(bare_expanded, "down").last).to be_nil
      expect(press(at(state, "s:paper.md#intro"), "down").last).to be_nil
      _, command = press(at(bare_expanded, "d:10"), "down")
      expect(command.call.section_id).to eq("paper.md#intro")
    end

    it "switches focus between the panes with tab and resets the clause cursor" do
      tree_focus = state.with(clause_cursor: 2)

      expect(press(tree_focus, "tab")).to eq([state.with(focus: :clauses, clause_cursor: 0), nil])
      expect(press(tree_focus.with(focus: :clauses), "tab")).to eq([state, nil])
    end

    it "expands with enter, right and l, and returns no command" do
      collapsed = at(state, "s:paper.md#intro").with(expanded: state.expanded - ["s:paper.md#intro"])
      expanded = state.expanded | ["s:paper.md#intro"]

      %w[enter right l].each do |key|
        expect(press(collapsed, key)).to eq([collapsed.with(expanded:), nil])
      end
      expect(press(at(state, "s:paper.md#intro"), "enter"))
        .to eq([at(state, "s:paper.md#intro").with(expanded: state.expanded - ["s:paper.md#intro"]), nil])
    end

    it "does not expand a row whose only children are clauses, nor an empty tree" do
      method = at(state, "s:paper.md#method")
      empty = SFL::TUI::Browse::State.initial

      expect(press(method, "enter")).to eq([method, nil])
      expect(press(empty, "enter")).to eq([empty, nil])
    end

    it "expands a document whose sections have clauses loaded" do
      collapsed = at(state, "d:10").with(expanded: state.expanded - ["d:10"])

      expect(press(collapsed, "enter").first.expanded).to eq(state.expanded)
    end

    it "toggles the focused tree row with space and returns no command" do
      selected, command = press(at(state, "d:11"), " ")

      expect(command).to be_nil
      expect(selected.selection.ids).to eq(Set["d:11", "s:talk.srt#turn-1", "s:talk.srt#turn-2", "k:t1", "k:t2"])
      expect(selected.with(selection: state.selection)).to eq(at(state, "d:11"))
    end

    it "leaves the state alone on space when no node is focused" do
      clauses = at(state, "d:10").with(focus: :clauses)

      expect(press(clauses, " ")).to eq([clauses, nil])
    end

    it "selects the level with a and clears with esc, returning no command" do
      all, command = press(at(state, "c:1"), "a")
      cleared, clear_command = press(all, "esc")

      expect(command).to be_nil
      expect(all.selection.ids).to include("c:1", "c:2")
      expect(all.with(selection: state.selection)).to eq(at(state, "c:1"))
      expect(clear_command).to be_nil
      expect(cleared.selection.ids).to be_empty
      expect(cleared.with(selection: state.selection)).to eq(at(state, "c:1"))
    end

    it "cycles the filter with f, resetting both cursors" do
      moved = state.with(cursor: 3, clause_cursor: 1)

      expect(press(moved, "f")).to eq([state.with(filter: "pending"), nil])
    end

    it "opens the export overlay with e only when the selection is not empty" do
      selected = state.with(selection: state.selection.select(state.tree, "d:20"))

      expect(press(state, "e")).to eq([state, nil])
      expect(press(selected, "e")).to eq([selected.with(overlay: :export), nil])
    end

    it "keeps the state and returns a load command with r" do
      next_state, command = press(state, "r")

      expect(next_state).to equal(state)
      expect(command).to be_a(Proc)
    end

    it "exports markdown with m and closes the overlay; ignores bound keys while it is open" do
      exporter = instance_double(SFL::Export::Exporter, call: { path: "/out/p.md", count: 1 })
      open = state.with(overlay: :export, selection: state.selection.select(state.tree, "s:paper.md#method"))
      closed, command = described_class.call(open, TUISpecSupport.key("m"), services.with(exporter:))
      command.call

      expect(closed).to eq(open.with(overlay: nil))
      expect(exporter).to have_received(:call).with(open.picks, :markdown)
      expect(press(open, "esc")).to eq([open.with(overlay: nil), nil])
      expect(press(open, "down")).to eq([open, nil])
      expect(press(open, "A")).to eq([open, nil])
    end

    it "returns the state and no command for review keys without a review item" do
      document = at(state, "d:10")

      %w[A R E o z].each { |key| expect(press(document, key)).to eq([document, nil]) }
    end

    it "keeps the state for review keys on a section with an item" do
      method = at(state, "s:paper.md#method")

      %w[A R E o].each { |key| expect(press(method, key).first).to equal(method) }
    end

    it "ignores E on a decided item and o on a non-image item" do
      decided = at(state, "s:talk.srt#turn-1")

      expect(press(decided, "E")).to eq([decided, nil])
      expect(press(decided, "R")).to eq([decided, nil])
      expect(press(decided, "o")).to eq([decided, nil])
    end

    it "recompiles an edited section under its collection's name" do
      run_log = SFL::Core::Ports::Fake::RunLog.new
      _, command = described_class.call(at(state, "s:paper.md#method"), TUISpecSupport.key("E"),
        services.with(run_log:, review_queue: instance_spy(SFL::Store::PgReviewQueueRepository)))
      command.call

      expect(run_log.rows.values.map { |row| row[:collection] }).to eq(["papers"])
    end

    it "expands the roots when the first load arrives and keeps an existing expansion" do
      first, = described_class.call(SFL::TUI::Browse::State.initial, loaded_message, services)
      kept, = described_class.call(SFL::TUI::Browse::State.initial.with(expanded: Set["c:2"]), loaded_message, services)

      expect(first.expanded).to eq(Set["c:1", "c:2"])
      expect(first.expanded).to be_a(Set)
      expect(kept.expanded).to eq(Set["c:2"])
    end

    it "replaces the tree and reviews, drops vanished selections and clamps the cursor on load" do
      message = loaded_message
      before = SFL::TUI::Browse::State.initial.with(cursor: 9, selection: SFL::TUI::Browse::Selection.new(%w[d:20 k:gone]))
      next_state, command = described_class.call(before, message, services)

      expect(next_state.tree).to equal(message.tree)
      expect(next_state.reviews).to equal(message.reviews)
      expect(next_state.selection.ids).to eq(Set["d:20"])
      expect(next_state.cursor).to eq(4)
      expect(command).to be_nil
    end

    it "loads the clauses of the focused section when the tree arrives" do
      before = SFL::TUI::Browse::State.initial.with(cursor: 2, expanded: Set["c:1", "d:10"])
      next_state, command = described_class.call(before, loaded_message, services)

      expect(next_state.cursor).to eq(2)
      expect(command.call.section_id).to eq("paper.md#intro")
    end

    it "keeps a selected section whole once its clauses arrive" do
      selected = bare.with(selection: bare.selection.select(bare.tree, "s:paper.md#method"))
      message = SFL::TUI::Messages::ClausesLoaded.new(section_id: "paper.md#method", clauses: source.clauses("paper.md#method"))
      next_state, command = described_class.call(selected, message, services)

      expect(command).to be_nil
      expect(next_state.selection.ids).to include("s:paper.md#method", "k:m1")
      expect(next_state.tree.clauses("s:paper.md#method").map(&:id)).to eq(["k:m1"])
      expect(next_state.with(tree: bare.tree, selection: bare.selection)).to eq(bare)
    end

    it "returns exactly a state and a nil command from the selection and clause-load transitions" do
      message = SFL::TUI::Messages::ClausesLoaded.new(section_id: "paper.md#method", clauses: source.clauses("paper.md#method"))

      [press(at(state, "c:1"), "a"), press(state, "esc"), described_class.call(bare, message, services)].each do |result|
        expect(result.size).to eq(2)
        expect(result.last).to be_nil
      end
    end

    it "steps the clause cursor from its current position" do
      three = %w[x1 x2 x3].map { |id| TUISpecSupport.clause(id, id) }
      tree = state.tree.with_clauses("paper.md#intro", three)
      clauses = at(state.with(tree:), "s:paper.md#intro").with(focus: :clauses, clause_cursor: 1)

      expect(press(clauses, "down").first.clause_cursor).to eq(2)
      expect(press(clauses.with(clause_cursor: 2), "up").first.clause_cursor).to eq(1)
    end

    it "loads the clauses of an unloaded section reached with up" do
      method = at(bare.with(expanded: Set["c:1", "d:10"]), "s:paper.md#method")
      _, command = press(method, "up")

      expect(command.call.section_id).to eq("paper.md#intro")
    end

    it "cycles the filter from its current value" do
      expect(press(state.with(filter: "pending"), "f").first.filter).to eq("accepted")
      expect(press(state.with(filter: "rejected"), "f").first.filter).to eq("all")
    end

    it "returns the same state and no command for clauses of an unknown section" do
      message = SFL::TUI::Messages::ClausesLoaded.new(section_id: "nope", clauses: [])

      expect(described_class.call(bare, message, services)).to eq([bare, nil])
    end
  end
end
