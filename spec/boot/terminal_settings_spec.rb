# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Boot::TerminalSettings do
  def settings(env) = SFL::Boot.terminal_settings(env:, load_dotenv: false)

  it "reads the reviewer, editor and export directory from the environment" do
    resolved = settings("SFL_REVIEWER_NAME" => " ana ", "VISUAL" => "code -w", "EDITOR" => "nano", "SFL_EXPORT_DIR" => "/x")

    expect(resolved).to eq(described_class.new(reviewer: "ana", editor: "code -w", export_dir: "/x",
      ingest_log_dir: "./output/logs", kitty_window_id: nil, kitty_listen_on: nil))
  end

  # Facts 67 and 72: Boot reads the kitty variables and the launcher log directory.
  it "reads KITTY_WINDOW_ID, KITTY_LISTEN_ON and SFL_INGEST_LOG_DIR" do
    resolved = settings("KITTY_WINDOW_ID" => "20", "KITTY_LISTEN_ON" => "unix:/tmp/mykitty-1", "SFL_INGEST_LOG_DIR" => "/logs")

    expect(resolved).to have_attributes(kitty_window_id: "20", kitty_listen_on: "unix:/tmp/mykitty-1", ingest_log_dir: "/logs")
  end

  it "falls back to EDITOR, then vi, and to ./output/exports, with no reviewer" do
    expect(settings("EDITOR" => "nano")).to have_attributes(editor: "nano", export_dir: "./output/exports", reviewer: nil)
    expect(settings("SFL_REVIEWER_NAME" => "  ").editor).to eq("vi")
    expect(settings("SFL_REVIEWER_NAME" => "  ").reviewer).to be_nil
  end
end
