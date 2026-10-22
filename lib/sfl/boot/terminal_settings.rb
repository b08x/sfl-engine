# frozen_string_literal: true

module SFL
  module Boot
    # Settings the terminal UI reads from the environment, resolved by
    # Boot.terminal_settings.
    #
    # - `reviewer`: SFL_REVIEWER_NAME, nil when unset; review decisions are
    #   refused without it
    # - `editor`: VISUAL, else EDITOR, else "vi"
    # - `export_dir`: SFL_EXPORT_DIR, else "./output/exports"
    # - `ingest_log_dir`: SFL_INGEST_LOG_DIR, else "./output/logs"; where a
    #   launcher ingest started outside kitty writes its output
    # - `kitty_window_id`, `kitty_listen_on`: KITTY_WINDOW_ID and
    #   KITTY_LISTEN_ON, nil when unset; Core::Ports::KittyHost.detect
    #   chooses kitty from them
    TerminalSettings = Data.define(:reviewer, :editor, :export_dir, :ingest_log_dir, :kitty_window_id, :kitty_listen_on)
  end
end
