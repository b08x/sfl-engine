# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Boot, ".eval_sources" do
  let(:workspace) { "/ws" }

  it "defaults to the export layout beside the engine checkout" do
    sources = described_class.eval_sources(workspace:, env: {}, load_dotenv: false)

    expect(sources).to eq(
      claude: "/ws/Datasets/ClaudeExports/2026-09-27/conversations-000/conversations.json",
      chatgpt: "/ws/Datasets/ChatGPTexport/*/conversations-003.json",
      mistral: "/ws/Datasets/MistralLeChatExports/2026-10-01/chat-export-1790856293990/" \
        "chat-aca44f91-4a8f-4233-a1e9-ab72c3b6b95f.json",
      notebooklm: File.expand_path("~/NotebookLM/The Disruption of Existential Anchors_assets/" \
        "artifacts/The_Real_AI_Threat_Is_Human_Paranoia_nlp.jsonl")
    )
  end

  it "lets SFL_EVAL_*_EXPORT variables override each path" do
    env = { "SFL_EVAL_CLAUDE_EXPORT" => "/x/claude.json", "SFL_EVAL_NOTEBOOKLM_FILE" => "/x/nlm.jsonl" }
    sources = described_class.eval_sources(workspace:, env:, load_dotenv: false)

    expect(sources).to include(claude: "/x/claude.json", notebooklm: "/x/nlm.jsonl")
  end

  it "ignores empty overrides" do
    sources = described_class.eval_sources(workspace:, env: { "SFL_EVAL_MISTRAL_EXPORT" => "" }, load_dotenv: false)

    expect(sources[:mistral]).to start_with("/ws/Datasets/MistralLeChatExports/")
  end
end
