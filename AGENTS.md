# AGENTS.md

Instructions for coding agents working in this repository. See `README.md` for the project overview.

## Commands

- `bundle exec rake` runs RSpec, RuboCop and the Zeitwerk check. Run it before finishing any change.
- `bundle exec rspec spec/path/to_spec.rb` runs one spec file.
- `bundle exec rake db:migrate` applies migrations.

## Config

- `SFL::Boot` is the only code that accesses `ENV`. Other classes receive configuration as arguments.
- `SFL_LOG_TARGET` is a comma-separated list (`stderr`, `journald`). The default is `stderr`. Every log call goes to every listed target. An unknown name, or `journald` without `/run/systemd/journal/socket`, raises `Boot::Error`.
- `SFL_RUN_ID` is attached to every log line. It is generated per process when unset. `rake eval:run_unseen` sets one per item. Query it with `journalctl SFL_RUN_ID=<id>`.
- The CLI writes `progress turn=N total=M` to stderr after each finished turn.
- Document new variables in `.env.example`.

## Conventions

- Log through `Ports::Logger`. Pass state as keyword fields, not interpolated strings.
- Every file under `lib/` has a spec at the matching path under `spec/`. For example, `lib/sfl/llm/engine.rb` has `spec/llm/engine_spec.rb`.
- `lib/` is loaded by Zeitwerk. File names match constant names.
- Do not edit `.env`. Do not commit secrets.

## Layout

- `lib/sfl/` holds application code. `spec/` mirrors it.
- `rakelib/` holds rake tasks.
- `exe/` holds executables.
- `goals/` holds feature goals and fact lists.
