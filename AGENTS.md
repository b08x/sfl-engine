# AGENTS.md

Instructions for coding agents working in this repository. See `README.md` for the project overview.

## Commands

- `bundle exec rake` runs RSpec, RuboCop and the Zeitwerk check. Run it before finishing any change.
- `bundle exec rspec spec/path/to_spec.rb` runs one spec file.
- `bundle exec rake db:migrate` applies migrations.
- `bundle exec rake db:purge_collection[NAME]` deletes a collection with its documents, sections and clauses.
- `bundle exec rake models:refresh` fills the `models` table from the model catalogs.

## Config

- `SFL::Boot` is the only code that reads `ENV`. Other classes receive configuration as arguments. `spec/tui/consolidation_spec.rb` fails on an `ENV` read under `lib/`, `exe/` or `rakelib/` outside `lib/sfl/boot*`, and on an `SFL_*` name missing from `.env.example`.
- `SFL_LOG_TARGET` is a comma-separated list (`stderr`, `journald`). The default is `stderr`. Every log call goes to every listed target. An unknown name, or `journald` without `/run/systemd/journal/socket`, raises `Boot::Error`.
- Task models resolve as env var, then `task_models` row, then default (`Boot::TaskModelResolver`). Without the database only env and defaults apply.
- `SFL_RUN_ID` is attached to every log line. It is generated per process when unset. `rake eval:run_unseen` sets one per item. Query it with `journalctl SFL_RUN_ID=<id>`.
- When stdout and stderr are both terminals, a foreground ingest or annotation run draws a full-screen dashboard (`SFL::Dashboard`). The stderr log target then goes to the dashboard's log panel; journald is unaffected. Ctrl-C sets the stop flag; a second Ctrl-C quits at once.
- Otherwise the CLI writes `progress turn=N total=M` to stderr after each finished turn.
- Stored runs write their progress to the `runs` table, keyed by `SFL_RUN_ID` (`CLI::PgRunProgressSink`).
- `sfl-tui` reads `SFL_REVIEWER_NAME` (review decisions are refused without it), `SFL_EXPORT_DIR` (default `./output/exports`), `SFL_INGEST_LOG_DIR` (default `./output/logs`), `$VISUAL`/`$EDITOR`, `KITTY_WINDOW_ID` and `KITTY_LISTEN_ON` through `Boot.terminal_settings`.
- `Core::Ports::TerminalHost` has two adapters. `KittyHost` runs `kitten @ --to $KITTY_LISTEN_ON launch ...` through an injectable runner (`TTY::Command` by default); `KittyHost.detect` chooses it only when `KITTY_WINDOW_ID` is set and the `KITTY_LISTEN_ON` socket exists. `Null::TerminalHost` answers `false`. A `TerminalHost::Error` is rescued at the TUI command and the command falls back: the ingest launcher starts a detached child (`TUI::Launcher::DetachedChild`), and the image key uses `Core::Ports::XdgOpener`. Specs use `Fake::TerminalHost` or a fake runner and never call kitty.
- Document new variables in `.env.example`.

## Conventions

- Log through `Ports::Logger`. Pass state as keyword fields, not interpolated strings.
- Every file under `lib/` has a spec at the matching path under `spec/`. For example, `lib/sfl/llm/engine.rb` has `spec/llm/engine_spec.rb`.
- `lib/` is loaded by Zeitwerk. File names match constant names.
- Do not edit `.env`. Do not commit secrets.
- The TUI (`lib/sfl/tui/`) is a pure update over immutable state. `Program.update(state, message, services)` returns the new state and at most one command; commands are Procs built with `SafeCommand` that do the I/O and return the next message. Specs drive it with `Core::Ports` fakes and render into ratatui's test terminal (`RatatuiRuby.init_test_terminal`). A tab is a module answering `TITLE`, `initial`, `init`, `update`, `handles?`, `capturing?`, `help`, `status` and `render`; add it to `Program::TABS`.
- There is no desktop GUI. Review happens in the TUI's Browse tab.

## Glossary

- Collection: a named group of documents.
- Document: one whole item, such as a paper, a transcript or one chat conversation.
- Section: a segment of a document, such as a heading block or one speaker turn. Identified by `section_id`, for example `file#turn-3`.
- Clause: what annotation produces from a section. Each clause row carries the `section_id` of its section.
- Use "document" only for a whole item and "section" for a segment of one.
- `document_key` identifies a document. The one `document_id` column is the `sections.document_id` foreign key to `documents.id`.

## Layout

- `lib/sfl/` holds application code. `spec/` mirrors it.
- `rakelib/` holds rake tasks.
- `exe/` holds executables.
- `goals/` holds feature goals and fact lists.
