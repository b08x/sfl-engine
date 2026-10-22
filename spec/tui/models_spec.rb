# frozen_string_literal: true

require_relative "spec_helper"

# Facts 60 to 64: the Models tab.
RSpec.describe SFL::TUI::Models do
  let(:models) do
    [
      model("ollama", "embeddinggemma:latest", ["embedding"]),
      model("ollama", "nomic-embed-text", ["embedding"]),
      model("openrouter", "a/chat", %w[chat vision]),
      model("openrouter", "b/old", ["chat"], available: false),
    ]
  end
  let(:store) do
    SFL::Core::Ports::Fake::ModelStore.new(models:,
      assignments: { loader_drafting: { provider: "openrouter", model_id: "b/old" } })
  end
  let(:env) { { "SFL_TASK_PASS_TWO_ANNOTATION_MODEL" => "a/chat" } }
  let(:refreshes) { [] }
  let(:refresher) do
    outcome = SFL::LLM::ModelRefresher::Outcome.new(catalog: "ollama", upserted: 2, unavailable: 0, error: nil)
    instance_double(SFL::LLM::ModelRefresher).tap { |double| allow(double).to receive(:call) { (refreshes << 1) && [outcome] } }
  end
  let(:services) do
    SFL::TUI::Services.null(model_store: store, model_resolver: SFL::Boot::TaskModelResolver.new(env:, store:),
      model_refresher: refresher)
  end

  def model(provider, model_id, capabilities, available: true)
    { provider:, model_id:, name: model_id, context_window: 8192, capabilities:, pricing: {}, available:, fetched_at: nil }
  end

  def loaded = deliver(described_class.initial, described_class.init(services).call)

  def deliver(state, message) = described_class.update(state, message, services).first

  def press(state, *keys)
    keys.reduce([state, nil]) do |(current, _), key|
      next_state, command = described_class.update(current, TUISpecSupport.key(key), services)
      command ? [deliver(next_state, command.call), command] : [next_state, nil]
    end
  end

  def screen(state) = TUISpecSupport.render(width: 220, height: 12) { |frame, tui| described_class.render(state, frame, frame.area, tui) }

  def task_line(lines, task) = lines.find { |line| line.include?(task.to_s) }

  it "answers the tab protocol" do
    expect(described_class::TITLE).to eq("Models")
    expect(described_class.handles?(SFL::TUI::Messages::ModelsLoaded.new(tasks: [], models: [], notice: nil))).to be(true)
    expect(described_class.handles?(TUISpecSupport.key("x"))).to be(false)
    expect(described_class.capturing?(described_class.initial)).to be(false)
    expect(described_class.help(nil)).to include("enter choose", "r refresh")
    expect(described_class.status(described_class.initial)).to be_nil
    expect(described_class.update(described_class.initial, :other, services)).to eq([described_class.initial, nil])
    expect(described_class.status(loaded)).to eq("7 tasks, 4 models")
  end

  it "lists each task with its effective provider, model and source (fact 60)" do
    lines = screen(loaded)

    expect(lines[1]).to include("task", "provider", "model", "source")
    expect(task_line(lines, "pass_two_annotation ")).to include("openrouter", "a/chat", "env")
    expect(task_line(lines, "loader_drafting")).to include("openrouter", "b/old", "db")
    expect(task_line(lines, "context_synthesis")).to include("openrouter", "a/chat", "default")
  end

  it "shows env-set tasks as locked with the variable's name, and refuses to change them (fact 61)" do
    state = loaded
    lines = screen(state)

    expect(task_line(lines, "pass_two_annotation ")).to include("locked SFL_TASK_PASS_TWO_ANNOTATION_MODEL")
    chosen, = press(state, "enter")
    expect(chosen.focus).to eq(:tasks)
    expect(described_class.status(chosen)).to eq("pass_two_annotation is locked by SFL_TASK_PASS_TWO_ANNOTATION_MODEL")
  end

  it "saves the model chosen for a task to task_models (fact 62)" do
    state = loaded
    state = state.with(cursor: state.tasks.index { |task| task[:task] == :embedding })

    chosen, = press(state, "enter")
    expect(chosen.focus).to eq(:models)
    saved, command = press(chosen, "down", "enter")

    expect(command).not_to be_nil
    expect(store.assignments[:embedding]).to eq(provider: "ollama", model_id: "nomic-embed-text")
    expect(saved.focus).to eq(:tasks)
    expect(saved.task).to include(source: :db, model: "nomic-embed-text")
    expect(described_class.status(saved)).to eq("embedding -> ollama/nomic-embed-text")
  end

  it "lists only models with the capability the task needs (fact 63)" do
    state = loaded
    embedding = state.with(cursor: state.tasks.index { |task| task[:task] == :embedding })
    chat = state.with(cursor: state.tasks.index { |task| task[:task] == :loader_drafting })

    expect(screen(embedding).join("\n")).to include("Models (embedding)", "nomic-embed-text")
    expect(embedding.candidates.map { |row| row[:model_id] }).to eq(["embeddinggemma:latest", "nomic-embed-text"])
    expect(chat.candidates.map { |row| row[:model_id] }).to eq(["a/chat", "b/old"])
  end

  it "marks a task whose assigned model is unavailable (fact 64)" do
    lines = screen(loaded)

    expect(task_line(lines, "loader_drafting")).to include("! unavailable")
    expect(task_line(lines, "pass_two_batch")).not_to include("! unavailable")
  end

  it "moves the cursors, backs out with esc, and opens on the task's current model" do
    state = loaded.then { |s| s.with(cursor: s.tasks.index { |task| task[:task] == :loader_drafting }) }

    chosen, = press(state, "enter")
    expect(chosen.model_cursor).to eq(1)
    expect(press(chosen, "up", "k").first.model_cursor).to eq(0)
    expect(press(chosen, "j", "x", "esc").first.focus).to eq(:tasks)
    expect(press(state.with(cursor: 0), "up", "j", "down", "x").first.cursor).to eq(2)
  end

  it "refreshes the models table with r and reports each catalog" do
    refreshed, = press(loaded, "r")

    expect(refreshes).to eq([1])
    expect(described_class.status(refreshed)).to eq("ollama: 2 listed, 0 unavailable")
  end

  it "does nothing on enter with no tasks or no models" do
    empty = described_class.initial

    expect(press(empty, "enter").first).to eq(empty)
    expect(press(empty.with(focus: :models), "enter")).to eq([empty.with(focus: :models), nil])
    expect(screen(empty).first).to include("Tasks")
  end

  it "turns a store failure into a Failed message" do
    broken = instance_double(SFL::Core::Ports::Fake::ModelStore)
    allow(broken).to receive(:list).and_raise(IOError, "db down")
    failing = SFL::TUI::Services.null(model_store: broken)

    expect(described_class.init(failing).call.to_s).to eq("models: IOError: db down")
  end
end
