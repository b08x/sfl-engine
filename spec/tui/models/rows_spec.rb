# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe SFL::TUI::Models::Rows do
  let(:resolution) do
    SFL::Boot::TaskModelResolver::Resolution.new(task: :embedding, provider: :ollama, model: "e", source: :env,
      env_var: "EMBEDDING_MODEL", params: {})
  end
  let(:models) { [{ provider: "ollama", model_id: "e", context_window: nil, capabilities: ["embedding"], available: false }] }

  it "builds task rows with the capability and the unavailable flag" do
    expect(described_class.tasks({ embedding: resolution }, models)).to eq([
{
  task: :embedding,
  provider: "ollama",
  model: "e",
  source: :env,
  env_var: "EMBEDDING_MODEL",
  capability: "embedding",
  unavailable: true,
},
])
  end

  it "draws task and model cells" do
    task = described_class.tasks({ embedding: resolution }, models).first

    expect(described_class.task_cell(task)).to eq(["embedding", "ollama", "e", "env", "locked EMBEDDING_MODEL ! unavailable"])
    expect(described_class.task_cell(task.merge(model: nil, source: :default, unavailable: false)))
      .to eq(["embedding", "ollama", "-", "default", ""])
    expect(described_class.model_cell(models.first)).to eq(["ollama", "e", "-", "unavailable"])
    expect(described_class.model_cell(models.first.merge(context_window: 9, available: true))).to eq(["ollama", "e", "9", ""])
  end

  it "filters models by capability" do
    expect(described_class.candidates(models, "chat")).to eq([])
    expect(described_class.candidates(models, "embedding")).to eq(models)
  end
end
