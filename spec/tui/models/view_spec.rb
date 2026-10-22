# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe SFL::TUI::Models::View do
  let(:task) do
    { task: :embedding, provider: "ollama", model: "e", source: :db, env_var: nil, capability: "embedding", unavailable: true }
  end
  let(:models) do
    [
      { provider: "ollama", model_id: "e", context_window: nil, capabilities: ["embedding"], available: false },
      { provider: "ollama", model_id: "f", context_window: 512, capabilities: ["embedding"], available: true },
      { provider: "openrouter", model_id: "chat", context_window: 1, capabilities: ["chat"], available: true },
    ]
  end
  let(:state) { SFL::TUI::Models.initial.with(tasks: [task], models:) }

  def screen(state) = TUISpecSupport.render(width: 160, height: 8) { |frame, tui| described_class.render(state, frame, frame.area, tui) }

  it "draws the tasks beside the selected task's candidate models" do
    lines = screen(state)

    expect(lines.first).to include("Tasks", "Models (embedding)")
    expect(lines[2]).to include("embedding", "ollama", "db", "! unavailable", "unavailable")
    expect(lines[3]).to include("f", "512")
    expect(lines.join("\n")).not_to include("openrouter")
  end

  it "titles the model pane plainly with no tasks" do
    expect(screen(SFL::TUI::Models.initial).first).to include("Tasks", "Models")
  end
end
