# CLI Hexagon — Refactor User Stories

**Project**: `sfl-engine` · **Branch**: `feature/roda_api` · **Date**: 2026-09-13

**Scope**: Unify the four separate executable entry points (`sfl-analyze`, `sfl-tui`, `sfl-api`, `sfl-review`) into a **single `sfl-engine` executable** with subcommands, behind a Hexagonal (ports/adapters) boundary — with **mode flags (`--tui`, `--gui`, `--api`)** that launch interactive or daemon modes for any subcommand, all sharing the same composition root (`Providers::Engine`).

This document addresses the [Plannotator feedback](https://github.com/b08x/sfl-engine/blob/feature/roda_api/docs/ecosystem-architecture.md#1-global-feedback-about-the-file) on `ecosystem-architecture.md` §3.1: *"so that instead of separate binaries, `sfl-engine` is the main executable, with subcommands for `tui` `gui` `daemon(api)` (cli being the default way of operating the program — with their respective flags and acceptable args; optional aliases shortcuts; (sfl-engine-tui, sfl-engine-gui and sfl-engine-api) to be considered..."*

**Revision Note**: Based on Plannotator annotation feedback (2026-09-13), the original adapter-per-mode design has been **reimagined** to use a **mode-flag pattern** where subcommands accept `--tui` and `--gui` flags to switch between CLI, TUI, and GUI interfaces, with CLI flags taking precedence and interactive modes providing entry forms for the same parameters.

**Companion documents**:
- [`ecosystem-architecture.md`](../ecosystem-architecture.md) — the cross-repo target-state frame this refactor implements.
- [`INGEST-PARSER-HEXAGON-USER-STORIES.md`](INGEST-PARSER-HEXAGON-USER-STORIES.md) — the `TargetResolver` pattern reused here for input resolution.

**Revision Note 2**: Based on further Plannotator annotation feedback (2026-09-13), subcommand dispatch is **overhauled to use the `thor` gem** (already a Gemfile dependency alongside Roda) instead of a hand-rolled `Core::Registry`-based `EntryPoint`. `SFL::CLI::EntryPoint` is now a `Thor` subclass; each subcommand is a Thor command method. This project has no releases yet, so the deprecation-warning/phased-migration strategy in §3 is also removed — old binstubs are replaced outright, not deprecated with a warning period.

**Evidence policy**: every `path:line` below was read from the working tree on 2026-09-13. Anything the architecture needs that is not in the tree is labelled **does not exist yet**.

---

## 1. Context & Problem Statement

### 1.1 What already exists

Separate entry points exist today, each with its own boot sequence and its own way of reaching `Providers::Engine`:

| Entry point | File | Boot path | Mode | Purpose |
|---|---|---|---|---|
| `sfl-tui` | `exe/sfl-tui` | `lib/sfl.rb` → `SFL::TUI::App.build` → `SFL::TUI::App.run` | TUI | Interactive terminal UI |
| `sfl-api` | `exe/sfl-api` | `lib/sfl.rb` → `exec falcon serve -c config.ru` → Roda | Daemon | HTTP API server (Falcon → Roda) |
| `sfl-review` | `exe/sfl-review` | `lib/sfl.rb` → `lib/sfl/gui/review_queue_app.rb` → `SFL::GUI::ReviewQueueApp.new.launch` | GUI | Desktop review queue (Glimmer DSL) |

**Shared composition root**: `Providers::Engine` (`app/config/providers/engine.rb:7-12`) wraps `SFL::API::Context.build` (`lib/sfl/api/context.rb:56`), which is consumed by:
- Roda routes — `app/sfl.rb:42` via `def ctx = Providers::Engine.get`
- `SFL::TUI::App.build` — `lib/sfl/tui/app.rb:??` *(to be verified)*
- `SFL::GUI::ReviewQueueApp` — `lib/sfl/gui/review_queue_app.rb:??` *(to be verified)*

**Current binstub pattern**: Each `exe/sfl-*` file:
1. Expands `lib/` onto `$LOAD_PATH` (same pattern across all current binstubs)
2. Requires `lib/sfl.rb` (the Zeitwerk loader)
3. Calls `SFL::DockerServices.ensure_running!` (where present)
4. Delegates to a mode-specific runner

**Key insight from ecosystem-architecture §3.1**: SCC is *a* pluggable frontend, not *the* frontend. The same principle applies here: **`sfl-engine` must work completely independently of any single frontend**, and the **mode flags (`--tui`, `--gui`)** allow users to switch between interfaces while using the same subcommand and parameter set.

### 1.2 What is missing

1. **No unified entry point.** There is no `sfl-engine` command that dispatches to subcommands. The four binstubs are **peer executables**, not modes of one program.
2. **No Thor-based subcommand dispatch.** There is no `Thor` subclass mapping subcommand names to command implementations. Dispatch is hardcoded in shell scripts, not in Ruby.
3. **No shared boot for modes.** Each entry point re-implements its own boot logic (load path setup, Docker check, tracing setup).
4. **No mode flags.** There is no `--tui` or `--gui` flag to switch interfaces within a subcommand.
5. **No mode-interface unification.** The CLI, TUI, and GUI do not share a common parameter schema; adding `--tui` to a CLI command does not present the same options in an interactive form.
6. **`exe/sfl-review` overlap with SCC.** Per [`ecosystem-architecture.md` §4.1](../ecosystem-architecture.md#41-the-fourth-mode--a-decision-to-make), once SCC's review surface reaches parity, `exe/sfl-review` should be retired. This refactor implements that retirement by **not** shipping a `gui` mode flag for the `review` subcommand in the first phase.
7. **No db-maintenance rake tasks.** There is no `rake` task for pruning stale entries, running migrations, or other routine database upkeep — this maintenance is currently manual or ad hoc.

---

## 2. Target Architecture

### 2.1 Ports and adapters

The CLI refactor introduces **one new driving adapter port** for subcommand dispatch, implemented as a **`Thor` subclass**, and **mode handlers** that switch between CLI, TUI, and GUI interfaces based on flags:

| Port | Responsibility | Driven / driving | Concrete implementations | Status |
|---|---|---|---|---|
| `SFL::Core::Ports::EntryPoint` | Execute a subcommand with argv and mode flags | **driving** | `SFL::CLI::EntryPoint` (a `Thor` subclass), `SFL::CLI::ModeHandlers::TuiHandler`, `SFL::CLI::ModeHandlers::GuiHandler` | **does not exist yet** |

**Composition change**: `Providers::Engine` remains the **single composition root** for the *domain*. `SFL::CLI::EntryPoint < Thor` dispatches to subcommand implementations via Thor's own command methods, and **mode handlers** activate when `--tui` or `--gui` flags are present, wrapping the subcommand's CLI logic with an interactive interface. `thor` is already a Gemfile dependency (used alongside Roda), so no new gem is introduced.

**New module layout**:
```
lib/sfl/cli/
├── entry_point.rb              # NEW: SFL::CLI::EntryPoint < Thor — subcommand dispatch
├── dispatch.rb                 # NEW: shared --tui/--gui mode detection used by every Thor command method
├── mode_handlers/
│   ├── tui_handler.rb         # NEW: launches TUI for a subcommand, pre-populating from CLI args
│   ├── gui_handler.rb         # NEW: launches GUI for a subcommand (DEPRECATED per §4.1)
│   └── base_handler.rb        # NEW: shared interface for mode handlers
├── commands/
│   ├── ingest_command.rb      # NEW: handles `sfl-engine ingest` (full pipeline incl. embeddings) with --tui/--gui support
│   ├── query_command.rb       # NEW: handles `sfl-engine query` (retrieve, fine-grained flags/args) with --tui/--gui support
│   └── ...
└── cli.rb                       # EXISTING: logic extracted into command classes

exec/
├── sfl-analyze                # REPLACED by `sfl-engine ingest`
├── sfl-tui                   # REPLACED by `sfl-engine ingest --tui`
├── sfl-api                   # REPLACED by `sfl-engine api` (special case)
├── sfl-review                 # REPLACED by `sfl-engine review --gui` (then retired per §4.1)
└── sfl-engine                 # NEW: the unified entry point
```

**Mermaid hexagon** (Thor-based driving adapter with mode handlers):
```mermaid
flowchart TB
  subgraph DRIVING["Driving adapter"]
    ENTRY["EntryPoint (Thor)<br/>NEW"]
  end

  subgraph MODES["Mode handlers"]
    CLI["CLI mode<br/>(default)"]
    TUI["TUI mode<br/>--tui flag"]
    GUI["GUI mode<br/>--gui flag (DEPRECATED)"]
  end

  subgraph ROOT["Existing composition roots"]
    PRV["Providers::Engine.get<br/>app/config/providers/engine.rb:12"]
    CTX["API::Context.build<br/>lib/sfl/api/context.rb:56"]
  end

  ENTRY -->|"dispatches to"| CLI
  ENTRY -->|"--tui flag"| TUI
  ENTRY -->|"--gui flag"| GUI
  CLI --> PRV
  TUI -->|"uses same params"| PRV
  GUI -->|"uses same params"| PRV
```

### 2.2 Subcommand contract

The unified `sfl-engine` executable supports the following subcommands, each accepting **mode flags** (`--tui`, `--gui`) to switch interfaces:

| Subcommand | Aliases | Purpose | Mode support |
|---|---|---|---|
| `ingest` | `i`, `sfl-engine-ingest` | Full pipeline — ingest documents, conversations, knowledge-bases; generate embeddings; analyze; synthesize | CLI, TUI, GUI |
| `query` | `q`, `sfl-engine-query` | Retrieve, with fine-grained flags/args | CLI, TUI |
| `review` | `r`, `sfl-engine-review` | Review queue (DEPRECATED with GUI mode) | CLI, GUI |
| `api` | `d`, `daemon`, `sfl-engine-api`, `sfl-engine-daemon` | HTTP API server (Falcon → Roda) | **CLI only** (daemon mode) |
| `version` | `v`, `--version`, `-v` | Print version and exit | Built-in |
| `help` | `h`, `--help`, `-h` | Print usage and exit | Built-in |

**Default behavior (no subcommand given)**: `sfl-engine` presents an **interactive multi-select menu** listing the subcommands in the table above, so the user picks which one to run — there is no longer a single default subcommand that runs silently. The picked subcommand then runs in CLI mode unless `--tui`/`--gui` was also passed. `sfl-engine -` is equivalent to no argument and also opens the menu.

**Global flags** (apply to all subcommands):
- `--trace` / `--no-trace` — Enable/disable OpenTelemetry/Langfuse tracing (default: enabled if configured)
- `--docker` / `--no-docker` — Enable/disable Docker services auto-start (default: enabled)
- `--quiet` / `-q` — Suppress non-error output
- `--verbose` / `-V` — Increase log verbosity

**Mode flags** (mutually exclusive, only one per invocation):
- `--tui` — Launch interactive terminal UI for this subcommand. CLI flags provided take precedence; TUI prompts for missing required parameters.
- `--gui` — Launch desktop GUI for this subcommand (DEPRECATED per §4.1). CLI flags provided take precedence; GUI presents forms for missing required parameters.

**Subcommand-specific flags** are shared between CLI, TUI, and GUI modes. Each subcommand defines its parameter schema once, and all modes consume it.

### 2.3 Thor-based dispatch

`SFL::CLI::EntryPoint` is a **`Thor` subclass**. Each subcommand is a Thor command method with its own `method_option` flags (including `--tui`/`--gui`); Thor's own `commands` hash replaces a hand-rolled registry, and Thor's built-in `Thor::UndefinedCommandError`/`--help` handling replace custom `UnknownSubcommandError`/usage-printing. A small `Dispatch` module shared by every command method detects `--tui`/`--gui` and hands off to the matching mode handler:

```ruby
# lib/sfl/cli/entry_point.rb
require "thor"

module SFL
  module CLI
    class EntryPoint < Thor
      def self.exit_on_failure? = true

      # No subcommand given (bare `sfl-engine` or `sfl-engine -`): prompt
      # with an interactive multi-select menu instead of running any single
      # subcommand silently.
      def self.start(given_args = ARGV, config = {})
        given_args = [prompt_subcommand] if given_args.empty? || given_args == ["-"]
        super(given_args, config)
      end

      def self.prompt_subcommand
        require "tty-prompt"
        TTY::Prompt.new.select("Which sfl-engine command?", commands.keys - %w[help])
      end

      desc "ingest [ARGS]", "Full pipeline — ingest, embed, analyze, synthesize"
      method_option :tui, type: :boolean, desc: "Launch interactive TUI"
      method_option :gui, type: :boolean, desc: "Launch desktop GUI"
      method_option :source, type: :string
      method_option :collection, type: :string
      method_option :store, type: :boolean
      method_option :limit, type: :numeric
      def ingest(*args)
        Dispatch.run(Commands::IngestCommand.new(args, options: options), options: options)
      end

      desc "query [QUERY]", "Retrieve, with fine-grained flags/args"
      method_option :tui, type: :boolean, desc: "Launch interactive TUI"
      method_option :limit, type: :numeric
      method_option :filter, type: :string
      method_option :collection, type: :string
      def query(*args)
        Dispatch.run(Commands::QueryCommand.new(args, options: options), options: options)
      end

      desc "review", "Review queue (DEPRECATED with GUI mode, see §4.1)"
      method_option :gui, type: :boolean, desc: "Launch desktop GUI"
      method_option :limit, type: :numeric
      def review
        Dispatch.run(Commands::ReviewCommand.new([], options: options), options: options)
      end

      desc "api", "HTTP API server (Falcon → Roda)"
      method_option :port, type: :numeric
      method_option :host, type: :string
      def api
        Commands::ApiCommand.new([], options: options).run
      end
    end
  end
end
```

```ruby
# lib/sfl/cli/dispatch.rb
module SFL
  module CLI
    module Dispatch
      def self.run(command, options:)
        raise EntryPoint::ConflictingModeError, "--tui and --gui are mutually exclusive" if options[:tui] && options[:gui]

        if options[:tui]
          ModeHandlers::TuiHandler.new(command, pre_populated_args: options).run
        elsif options[:gui]
          ModeHandlers::GuiHandler.new(command, pre_populated_args: options).run
        else
          command.run
        end
      end
    end
  end
end
```

---

## 3. Replacement Strategy

This project has no releases yet, so there is no deprecation window and no warn-then-delegate shim: old binstubs are **replaced outright** by `sfl-engine`, in one commit, not deprecated across phases.

### 3.1 Migration path

| Old command | New command |
|---|---|
| `bundle exec exe/sfl-analyze <args>` | `bundle exec exe/sfl-engine ingest <args>` |
| `bundle exec exe/sfl-tui` | `bundle exec exe/sfl-engine ingest --tui` |
| `bundle exec exe/sfl-tui <args>` | `bundle exec exe/sfl-engine <subcommand> --tui <args>` |
| `bundle exec exe/sfl-api <args>` | `bundle exec exe/sfl-engine api <args>` |
| `bundle exec exe/sfl-review` | `bundle exec exe/sfl-engine review --gui` (until retired, see §4.1) |
| `bundle exec exe/sfl-review <args>` | `bundle exec exe/sfl-engine review --gui <args>` (until retired, see §4.1) |

`exe/sfl-analyze`, `exe/sfl-tui`, and `exe/sfl-api` are **deleted** the moment `exe/sfl-engine` ships (SFL-CLI-08/09). `exe/sfl-review` is deleted separately, once SCC review parity is reached (SFL-CLI-11).

### 3.2 Aliases

**Shell aliases** (for convenience, not shipped by the gem):
```bash
# ~/.bashrc or ~/.zshrc
alias sfl=sfl-engine
alias sfl-analyze='sfl-engine ingest'
alias sfl-tui='sfl-engine ingest --tui'
alias sfl-api='sfl-engine api'
```

**Symlink aliases** (shipped in the repo purely for scripting convenience — not a compatibility shim):
```bash
# In the repo root, created by `bin/roda g aliases` or manually:
ln -sf exe/sfl-engine exe/sfl-engine-ingest
ln -sf exe/sfl-engine exe/sfl-engine-tui
ln -sf exe/sfl-engine exe/sfl-engine-api
```

These symlinks:
1. Point to `exe/sfl-engine`
2. Are **not** committed to git (`.gitignore` entry)
3. Are created by a Rake task or `bin/roda` generator for local development
4. Note: `sfl-engine-tui` symlink maps to the `--tui` mode flag on `ingest`, not a separate subcommand

---

## 4. Epics

| Epic | Goal (one line) |
|---|---|
| **E1 — EntryPoint dispatch** | Introduce `SFL::CLI::EntryPoint < Thor` for subcommand dispatch with mode flag detection (`--tui`, `--gui`), and an interactive multi-select menu when no subcommand is given. |
| **E2 — Mode handlers** | Implement `TuiHandler` and `GuiHandler` that wrap command classes with interactive interfaces, sharing the same parameter schema. |
| **E3 — Subcommand implementations** | Extract `IngestCommand` (full pipeline, replaces the retired `analyze` subcommand), `QueryCommand` (retrieve, renamed from `ContextCommand`), `ApiCommand`, `ReviewCommand` from existing binstubs, each supporting mode flags. |
| **E4 — Unified entry point** | Ship `exe/sfl-engine` that reads argv[0] as subcommand, detects mode flags, dispatches via `EntryPoint`, and delegates to command + mode handler. |
| **E5 — Old binstub removal** | Delete `exe/sfl-analyze`, `exe/sfl-tui`, `exe/sfl-api` outright once `exe/sfl-engine` ships — no deprecation warnings or delegation shims (this project has no releases yet). |
| **E6 — GUI retirement** | Retire `exe/sfl-review` and the `--gui` mode flag once SCC review parity is achieved (per ecosystem-architecture §4.1). |
| **E7 — DB maintenance rake tasks** | Add `rake` tasks for routine database upkeep (pruning stale entries, running migrations). |

---

## 5. User Stories

Conventions every story inherits:
- Zeitwerk-compatible file layout under `lib/sfl/cli/` with no new inflections needed.
- `Dry::Monads` `Result` returns for anything that can fail at request time.
- `thor` is already a Gemfile dependency (used alongside Roda) — `SFL::CLI::EntryPoint` adopts it for subcommand dispatch; no new gem added to the Gemfile by any story here.
- RuboCop clean under the project's existing config.
- Existing test patterns preserved: `spec/cli/` mirrors `lib/sfl/cli/`.
- **Mode flag precedence**: CLI-provided arguments always take precedence over interactive input. Mode handlers pre-populate forms with CLI values.

---

### SFL-CLI-01 — Thor-based EntryPoint with subcommand dispatch and mode flag detection

**Points**: 5 · **Depends on**: none · **Epic**: E1

> **As a** platform engineer
> **I want** `SFL::CLI::EntryPoint < Thor` with per-command mode flag detection (`--tui`, `--gui`)
> **so that** subcommands can seamlessly switch between CLI, TUI, and GUI interfaces using the same parameter schema, without hand-rolling a registry Thor already gives us for free.

**Acceptance criteria**

- **Given** `SFL::CLI::EntryPoint`, **when** inspected, **then** it is a `Thor` subclass and `EntryPoint.commands.keys` includes `"ingest"`, `"query"`, `"review"`, `"api"` (Thor's own command table; no hand-rolled registry).
- **Given** `EntryPoint.start(["ingest", "conversation", "input.jsonl"])`, **then** Thor dispatches to the `#ingest` command method, which calls `Dispatch.run` with a `Commands::IngestCommand` instance and `options[:tui]`/`options[:gui]` both falsy.
- **Given** `EntryPoint.start(["unknown-command"])`, **then** Thor's own `Thor::UndefinedCommandError` handling prints "Could not find command \"unknown-command\"." and a usage hint — no custom `UnknownSubcommandError` needed.
- **Given** `EntryPoint.start(["ingest", "--tui", "conversation", "input.jsonl"])`, **then** `options[:tui]` is `true` and `Dispatch.run` delegates to `ModeHandlers::TuiHandler` with `pre_populated_args: options`.
- **Given** `EntryPoint.start(["ingest", "conversation", "input.jsonl"])` (no mode flag), **then** `Dispatch.run` calls `command.run` directly.
- **Given** `EntryPoint.start(["ingest", "--tui", "--gui", "input.jsonl"])`, **then** `Dispatch.run` raises `SFL::CLI::EntryPoint::ConflictingModeError` (mutually exclusive flags).
- **Given** `EntryPoint.start([])` or `EntryPoint.start(["-"])` (no subcommand given), **then** `EntryPoint.start` calls `EntryPoint.prompt_subcommand`, which presents an interactive multi-select menu (via `TTY::Prompt`) of `commands.keys - %w[help]`, and re-invokes `start` with whichever name the user selects — it does **not** silently run any single subcommand.
- **Given** `lib/sfl/cli/entry_point.rb`, **when** grepped, **then** it contains **no** `require` of `sequel`, `pgvector`, `roda`, `falcon`, `glimmer`, or `ENV` (except `ENV.fetch` with defaults for CLI flags like `--quiet`) — `require "thor"` and, lazily inside `prompt_subcommand`, `require "tty-prompt"` are expected.
- **Given** `lib/sfl/cli/entry_point.rb`, **when** loaded, **then** the built-in subcommands (`ingest`, `query`, `api`, `review`) are defined as Thor command methods with `desc`/`method_option` in the same file.

**Integration points**

- New file `lib/sfl/cli/entry_point.rb` (`SFL::CLI::EntryPoint < Thor`).
- New file `lib/sfl/cli/dispatch.rb` (`SFL::CLI::Dispatch.run`, shared `--tui`/`--gui` detection used by every command method).
- New directory `lib/sfl/cli/mode_handlers/` with base handler interface.
- Autoloaded by the `lib/` Zeitwerk loader configured at `lib/sfl.rb:38-44`; `CLI::EntryPoint` and `CLI::Dispatch` are camel-derivable.
- `thor` is already a Gemfile dependency (used alongside Roda) — no new gem addition.
- Built-in `help`/`version` behavior comes from Thor itself (`Thor::Base`'s default `help` command; `map %w[-v --version] => :version` with a small `version` command method for `sfl-engine --version`).

**Definition of done**:
- `spec/cli/entry_point_spec.rb` covers all criteria including the no-args menu case and mode detection.
- `bundle exec exe/sfl-engine help` prints Thor's usage message listing all registered subcommands.
- `bundle exec exe/sfl-engine --version` prints the version (from `lib/sfl/version.rb` or Git).
- RuboCop clean; no Gemfile change.

---

### SFL-CLI-02 — ModeHandlers for TUI and GUI modes

**Points**: 5 · **Depends on**: SFL-CLI-01 · **Epic**: E2

> **As a** user who prefers interactive interfaces
> **I want** `--tui` and `--gui` flags to launch interactive forms for any subcommand
> **so that** I can use the same command with a different interface.

**Acceptance criteria**

- **Given** `SFL::CLI::ModeHandlers::BaseHandler`, **when** inspected, **then** it defines a common interface: `#run(command, pre_populated_args:)` and `#interactive_prompt(command)`.
- **Given** `SFL::CLI::ModeHandlers::TuiHandler`, **when** instantiated with a command and `pre_populated_args: { source: "./docs", store: true }`, **then** calling `#run` launches the TUI, pre-populates the form with the provided args, and prompts only for missing required parameters.
- **Given** `SFL::CLI::ModeHandlers::GuiHandler`, **when** instantiated with a command and `pre_populated_args: { source: "./docs" }`, **then** calling `#run` launches the GUI, pre-populates the form fields, and shows input fields only for missing required parameters.
- **Given** a TUI/GUI handler with all required args pre-populated from CLI, **when** `#run` is called, **then** it executes the command immediately without showing any prompts.
- **Given** `lib/sfl/cli/mode_handlers/tui_handler.rb`, **when** grepped, **then** it contains **no** `require "glimmer-dsl-libui"` or `require "bubble-tea"` — those dependencies are **only** loaded lazily when the mode is activated.
- **Given** `lib/sfl/cli/mode_handlers/gui_handler.rb`, **when** grepped, **then** it contains **no** direct instantiation of GUI classes — it uses lazy loading via `SFL::GUI` namespace.
- **Given** both handlers, **when** CLI args conflict with TUI/GUI defaults, **then** CLI args take precedence (e.g., `--source /tmp` overrides any default in the TUI form).

**Integration points**

- New directory `lib/sfl/cli/mode_handlers/` with `base_handler.rb`, `tui_handler.rb`, `gui_handler.rb`.
- `tui_handler.rb` depends on existing `lib/sfl/tui/app.rb` infrastructure.
- `gui_handler.rb` depends on existing `lib/sfl/gui/` infrastructure.
- `spec/cli/mode_handlers/tui_handler_spec.rb` and `spec/cli/mode_handlers/gui_handler_spec.rb` verify pre-population and precedence.

**Definition of done**:
- `spec/cli/mode_handlers/` tests pass.
- `bundle exec exe/sfl-engine ingest --tui` launches the TUI with the ingest (full pipeline) form.
- `bundle exec exe/sfl-engine ingest --source ./docs --tui` pre-populates source and only prompts for missing fields.
- RuboCop clean.

---

### SFL-CLI-03 — IngestCommand as the full pipeline (retires `analyze`), with mode flag support

**Points**: 8 · **Depends on**: SFL-CLI-01, SFL-CLI-02 · **Epic**: E3

**Retirement note**: The `analyze` subcommand is retired. `IngestCommand` absorbs its full pipeline — ingest, embedding generation, analysis, synthesis — so `sfl-engine ingest` is now the one-shot equivalent of the old `sfl-analyze`. Pure retrieval moves to `QueryCommand` (SFL-CLI-05). This story supersedes the former SFL-CLI-04 (`AnalyzeCommand`), which is removed.

> **As a** user ingesting and analyzing content
> **I want** `sfl-engine ingest` to run the full pipeline (ingest, embed, analyze, synthesize) and accept `--tui` and `--gui` flags
> **so that** I can use an interactive form to enter pipeline parameters, with one subcommand replacing the old `analyze`/`ingest` split.

**Acceptance criteria**

- **Given** `SFL::CLI::Commands::IngestCommand`, **when** constructed with `argv: ["--source", "./docs", "--collection", "worknotes", "--store"]`, **then** it parses and validates the same options as the existing `sfl-analyze` ingest logic.
- **Given** a command with parsed options, **when** `#run` is called in CLI mode, **then** it executes the full pipeline (ingest → embed → analyze → synthesize) identically to `exe/sfl-analyze` with the same flags.
- **Given** `SFL::CLI::Commands::IngestCommand`, **when** constructed with `argv: ["conversation", "input.jsonl", "--store", "--limit", "10"]`, **then** it parses and validates the same options as `SFL::CLI.parse` (`lib/sfl/cli.rb:99-??`), the former entry point for `analyze`.
- **Given** `sfl-engine ingest --help`, **then** it prints the **same** usage text as `sfl-analyze --help` today (the `USAGE` constant at `lib/sfl/cli.rb:40-93`), minus any pure-retrieve flags now owned by `QueryCommand`.
- **Given** a command constructed with `argv: ["--tui"]`, **then** the `EntryPoint` detects `:tui` mode and delegates to `TuiHandler` with an empty `pre_populated_args` hash.
- **Given** a command constructed with `argv: ["--source", "./docs", "--tui"]`, **then** the `EntryPoint` detects `:tui` mode and delegates to `TuiHandler` with `pre_populated_args: { source: "./docs" }`.
- **Given** a command with `argv: ["conversation", "input.jsonl", "--store"]`, **then** the command's parameter schema identifies `input_type`, `input_path`, `store`, `limit` as the configurable parameters for TUI/GUI forms.
- **Given** an unknown flag passed to the command, **then** it raises `SFL::CLI::UsageError` with the same message format as the existing CLI.
- **Given** `lib/sfl/cli/commands/ingest_command.rb`, **when** grepped, **then** it contains **no** TUI or GUI code — only CLI parsing and execution logic.

**Integration points**

- New file `lib/sfl/cli/commands/ingest_command.rb`.
- Extracts and merges ingest logic and the former `analyze` pipeline logic from existing `lib/sfl/cli.rb`.
- `spec/cli/commands/ingest_command_spec.rb` tests CLI mode execution, mirroring the former `spec/cli/cli_spec.rb`.

**Definition of done**:
- `spec/cli/commands/ingest_command_spec.rb` passes.
- `bundle exec exe/sfl-engine ingest --source ./docs --collection worknotes --store` produces the same result as `bundle exec exe/sfl-analyze` with equivalent flags.
- `bundle exec exe/sfl-engine ingest conversation input.jsonl --store` produces the same result as `bundle exec exe/sfl-analyze conversation input.jsonl --store`.
- `bundle exec exe/sfl-engine ingest --tui` launches the TUI ingest (full pipeline) form.
- RuboCop clean.

---

### SFL-CLI-04 — Retired: merged into SFL-CLI-03

`AnalyzeCommand` and the `analyze` subcommand no longer exist. Their scope (ingest, analyze, synthesize) is folded into `IngestCommand` (SFL-CLI-03); retrieval moves to `QueryCommand` (SFL-CLI-05). This entry is kept as a placeholder so existing cross-references to `SFL-CLI-04` resolve to this note.

---

### SFL-CLI-05 — QueryCommand (retrieve) with fine-grained flags/args and mode flag support

**Points**: 5 · **Depends on**: SFL-CLI-01, SFL-CLI-02 · **Epic**: E3

**Renamed/expanded from `ContextCommand`**: `query` replaces the former `context` subcommand and absorbs the retrieve step from the retired `analyze` subcommand, exposing it through fine-grained flags and positional args rather than analyze's monolithic options.

> **As a** user retrieving previously ingested content
> **I want** `sfl-engine query` to accept fine-grained retrieve flags/args plus `--tui` and `--gui`
> **so that** I can use an interactive form to enter my query, with the same retrieve capability the old `analyze` subcommand offered.

**Acceptance criteria**

- **Given** `SFL::CLI::Commands::QueryCommand`, **when** constructed with `argv: ["what happened?", "--limit", "10"]`, **then** it parses and validates the same options as the existing context/retrieve query logic.
- **Given** a command with parsed options, **when** `#run` is called in CLI mode, **then** it executes the retrieve query and prints results identically to `exe/sfl-analyze`'s retrieve step, with the same flags.
- **Given** a command, **when** queried for its parameter schema, **then** it exposes the fine-grained retrieve flags/args (e.g. query string, `--limit`, `--filter`, `--collection`) that the old `analyze` subcommand bundled into one set of options.
- **Given** a command with `argv: ["--tui"]`, **then** the `EntryPoint` detects `:tui` mode and delegates to `TuiHandler` which prompts for the query string and optional parameters.
- **Given** a command with `argv: ["--limit", "10", "--tui"]`, **then** the `EntryPoint` detects `:tui` mode and delegates to `TuiHandler` with `pre_populated_args: { limit: "10" }`, prompting only for the query.
- **Given** `sfl-engine query --help`, **then** it prints usage text for the query subcommand.
- **Given** `lib/sfl/cli/commands/query_command.rb`, **when** grepped, **then** it contains **no** TUI or GUI code — only CLI parsing and execution logic.

**Integration points**

- New file `lib/sfl/cli/commands/query_command.rb`.
- Extracts context query logic from existing `lib/sfl/cli.rb`, plus the retrieve-step logic formerly in the `analyze` pipeline.
- `spec/cli/commands/query_command_spec.rb` tests CLI mode execution.

**Definition of done**:
- `spec/cli/commands/query_command_spec.rb` passes.
- `bundle exec exe/sfl-engine query "what happened?" --limit 10` produces the same result as `bundle exec exe/sfl-analyze`'s retrieve step with equivalent flags.
- `bundle exec exe/sfl-engine query --tui` launches the TUI with a query prompt.
- RuboCop clean.

---

### SFL-CLI-06 — ApiCommand (daemon mode)

**Points**: 3 · **Depends on**: SFL-CLI-01 · **Epic**: E3

> **As an** API operator
> **I want** `sfl-engine api` to start the HTTP server with the same flags as `sfl-api`
> **so that** the migration is transparent for API users.

**Acceptance criteria**

- **Given** `SFL::CLI::Commands::ApiCommand`, **when** constructed with `argv: ["--port", "3002", "--host", "localhost"]`, **then** it parses `PORT` and `HOST` from argv **or** ENV (argv takes precedence, matching `exe/sfl-api:20-21`).
- **Given** a command with `port: 3002`, `host: "localhost"`, **when** `#run` is called, **then** it executes `exec "bundle", "exec", "falcon", "serve", "-c", "config.ru", "-b", "http://localhost:3002"` (same as `exe/sfl-api:22-23`).
- **Given** no argv flags and no ENV, **then** it defaults to `port: "3001"`, `host: "0.0.0.0"` (same as `exe/sfl-api:20-21`).
- **Given** `sfl-engine api --tui`, **then** it raises `SFL::CLI::EntryPoint::InvalidModeError` with message: "`--tui` and `--gui` flags are not supported for the `api` subcommand (daemon mode only)".
- **Given** `sfl-engine api --gui`, **then** it raises the same `InvalidModeError`.
- **Given** `lib/sfl/cli/commands/api_command.rb`, **when** grepped, **then** it contains **no** `require "falcon"` or `require "roda"` — those dependencies are **only** in `config.ru` and the Roda app.

**Integration points**

- New file `lib/sfl/cli/commands/api_command.rb`.
- Reuses existing `config.ru` and `app/sfl.rb` unchanged.
- `spec/cli/commands/api_command_spec.rb` stubs `exec` and verifies the correct command is assembled.

**Definition of done**:
- `spec/cli/commands/api_command_spec.rb` passes.
- `bundle exec exe/sfl-engine api --port 3002 --host localhost` starts a server on `localhost:3002`.
- RuboCop clean.

---

### SFL-CLI-07 — ReviewCommand with GUI mode (DEPRECATED)

**Points**: 2 · **Depends on**: SFL-CLI-01, SFL-CLI-02 · **Epic**: E3

> **As a** review user (temporary)
> **I want** `sfl-engine review --gui` to launch the desktop review queue
> **so that** there is a migration path before SCC reaches parity.

**Acceptance criteria**

- **Given** `SFL::CLI::Commands::ReviewCommand`, **when** constructed with `argv: ["--gui"]`, **then** the `EntryPoint` detects `:gui` mode and delegates to `GuiHandler` for the review interface.
- **Given** a command with `argv: ["--limit", "20", "--gui"]`, **then** the `EntryPoint` detects `:gui` mode and delegates to `GuiHandler` with `pre_populated_args: { limit: "20" }`.
- **Given** `bundle exec exe/sfl-engine review --gui`, **then** it emits a **deprecation warning**:
  ```
  WARNING: `sfl-engine review --gui` is deprecated and will be removed once SCC's review surface reaches parity.
          See: docs/ecosystem-architecture.md §4.1
  ```
- **Given** `lib/sfl/cli/commands/review_command.rb`, **when** grepped, **then** it contains **no** direct GUI instantiation — only CLI parsing for review parameters.

**Integration points**

- New file `lib/sfl/cli/commands/review_command.rb`.
- Reuses existing `lib/sfl/gui/review_queue_app.rb` via `GuiHandler`.
- **This command's `--gui` mode is removed in SFL-CLI-09** (GUI retirement).

**Definition of done**:
- `spec/cli/commands/review_command_spec.rb` passes.
- `bundle exec exe/sfl-engine review --gui` launches the GUI and prints the deprecation warning.
- RuboCop clean.

---

### SFL-CLI-08 — Unified `sfl-engine` entry point

**Points**: 5 · **Depends on**: SFL-CLI-01, SFL-CLI-02, SFL-CLI-03, SFL-CLI-05, SFL-CLI-06, SFL-CLI-07 · **Epic**: E4

> **As a** user
> **I want** a single `sfl-engine` command that dispatches to subcommands with mode flag support
> **so that** I can use one entry point for all interfaces.

**Acceptance criteria**

- **Given** `exe/sfl-engine`, **when** it is invoked with no arguments (or `-`), **then** it presents an interactive multi-select menu listing `ingest`, `query`, `review`, `api`, and dispatches to the selected subcommand with an empty argv.
- **Given** `exe/sfl-engine ingest conversation input.jsonl`, **then** it dispatches to `IngestCommand` and produces the same output as `exe/sfl-analyze conversation input.jsonl`.
- **Given** `exe/sfl-engine ingest --tui conversation input.jsonl`, **then** it dispatches to `IngestCommand`, detects `:tui` mode, and delegates to `TuiHandler` with pre-populated args.
- **Given** `exe/sfl-engine ingest --source ./docs --tui`, **then** it dispatches to `IngestCommand`, detects `:tui` mode, and launches the TUI with source pre-populated.
- **Given** `exe/sfl-engine api`, **then** it dispatches to `ApiCommand` and starts the HTTP server.
- **Given** `exe/sfl-engine review --gui`, **then** it dispatches to `ReviewCommand`, detects `:gui` mode, and launches the GUI (with deprecation warning).
- **Given** `exe/sfl-engine help`, **then** Thor's own help output lists all registered subcommands, their short descriptions, and available mode flags (from `desc`/`method_option`).
- **Given** `exe/sfl-engine --version`, **then** it prints the version string (e.g., `sfl-engine 0.1.0` or Git SHA).
- **Given** `exe/sfl-engine unknown-command`, **then** Thor prints `Could not find command "unknown-command".` followed by the same usage hint as `help`.
- **Given** `exe/sfl-engine ingest --tui --gui`, **then** `Dispatch.run` raises `SFL::CLI::EntryPoint::ConflictingModeError` with message: `--tui and --gui are mutually exclusive`.
- **Given** `exe/sfl-engine`, **when** grepped, **then** it contains **no** mode-specific logic — only `SFL::CLI::EntryPoint.start(ARGV)`.

**Integration points**

- New file `exe/sfl-engine` (replaces the need for `exe/sfl-analyze`, `exe/sfl-tui`, `exe/sfl-api`, `exe/sfl-review`).
- Loads `lib/sfl.rb` via the same load path setup as the existing binstubs.
- Calls `SFL::DockerServices.ensure_running!` **before** dispatching to any subcommand (except `version` and `help`).
- Calls `SFL::CLI::EntryPoint.start(ARGV)` — Thor's own entry point, which handles the no-args menu (§2.3), mode flags via `Dispatch.run`, and subcommand lookup.

**Definition of done**:
- `spec/cli/sfl_engine_spec.rb` passes (tests the `exe/sfl-engine` script behavior with mode flags).
- `bundle exec exe/sfl-engine` with no arguments presents the multi-select subcommand menu and dispatches correctly on selection.
- `exe/sfl-analyze`, `exe/sfl-tui`, `exe/sfl-api` are deleted (SFL-CLI-09); `exe/sfl-review` remains until SFL-CLI-11.
- RuboCop clean.

---

### SFL-CLI-09 — Delete old binstubs (no deprecation shim)

**Points**: 1 · **Depends on**: SFL-CLI-08 · **Epic**: E5

**No-deprecation note**: This project has no releases yet — there is no installed base to warn, so there is no warn-then-delegate phase. `exe/sfl-analyze`, `exe/sfl-tui`, and `exe/sfl-api` are deleted in the same change that ships `exe/sfl-engine`. `exe/sfl-review` is the one exception: it is kept until SFL-CLI-11 retires it, gated on SCC review parity (an unrelated, functional gate — not a deprecation window).

> **As a** maintainer
> **I want** the old binstubs removed the moment `sfl-engine` ships
> **so that** there is exactly one CLI entry point, with no legacy shim to maintain.

**Acceptance criteria**

- **Given** `exe/sfl-engine` has shipped (SFL-CLI-08 done), **then** `exe/sfl-analyze`, `exe/sfl-tui`, and `exe/sfl-api` no longer exist in the repo (`ls exe/sfl-analyze` etc. fail).
- **Given** a user runs `bundle exec exe/sfl-analyze`, **then** the shell reports "No such file or directory" — there is **no** wrapper script that warns and delegates.
- **Given** `exe/sfl-review`, **then** it still exists and is **unmodified**; its removal is scoped to SFL-CLI-11, gated on SCC review parity.
- **Given** the repo's git history, **when** inspected, **then** the deletion of the three binstubs and the addition of `exe/sfl-engine` land in the same commit/PR.

**Integration points**

- Delete `exe/sfl-analyze`, `exe/sfl-tui`, `exe/sfl-api`.
- Leave `exe/sfl-review` untouched (handled by SFL-CLI-11).
- Update any README/AGENTS.md usage examples that still invoke the deleted binstubs directly.

**Definition of done**:
- `git status`/`ls exe/` confirms only `exe/sfl-engine`, `exe/sfl-review`, and the symlink aliases (SFL-CLI-10) remain.
- RuboCop clean.

---

### SFL-CLI-10 — Symlink aliases for backward compatibility

**Points**: 1 · **Depends on**: SFL-CLI-08 · **Epic**: E4

> **As a** scripter
> **I want** `sfl-engine-ingest`, `sfl-engine-tui`, etc. to work as symlinks to `sfl-engine`
> **so that** I can use either form in scripts.

**Acceptance criteria**

- **Given** a symlink `exe/sfl-engine-ingest` → `exe/sfl-engine`, **when** I run `bundle exec exe/sfl-engine-ingest conversation input.jsonl`, **then** it behaves identically to `bundle exec exe/sfl-engine ingest conversation input.jsonl`.
- **Given** a symlink `exe/sfl-engine-tui` → `exe/sfl-engine`, **when** I run `bundle exec exe/sfl-engine-tui`, **then** it behaves identically to `bundle exec exe/sfl-engine ingest --tui`.
- **Given** symlinks for `sfl-engine-api`, **then** they behave identically to their subcommand equivalents.
- **Given** the symlinks, **when** listed in git, **then** they are **not** tracked (added to `.gitignore`).

**Integration points**

- New Rake task `rake cli:symlinks` creates the symlinks in `exe/`.
- Or, new `bin/roda g cli:aliases` generator creates the symlinks.
- `.gitignore` entry: `/exe/sfl-engine-*`

**Definition of done**:
- `bundle exec rake cli:symlinks` creates all four symlinks.
- `bundle exec exe/sfl-engine-ingest --help` works.
- `bundle exec exe/sfl-engine-tui` launches the TUI.

---

### SFL-CLI-11 — Retire GUI mode flag and `exe/sfl-review`

**Points**: 2 · **Depends on**: SFL-CLI-08, SFL-CLI-09, SFL-CLI-10 · **Epic**: E6

> **As a** maintainer
> **I want** to remove the `--gui` mode flag and old `exe/sfl-review` binstub once SCC review parity is achieved
> **so that** we avoid maintaining two review clients.

**Acceptance criteria**

- **Given** the acceptance criteria for SCC review parity are met (per [`ecosystem-architecture.md` §4.1](../ecosystem-architecture.md#41-the-fourth-mode--a-decision-to-make):
  - SCC exposes `POST /clauses/:id/review`
  - SCC exposes `POST /review-queue/:id/decide`
  - SCC review surface is feature-complete relative to `exe/sfl-review`
- **When** this story is implemented, **then**:
  - `lib/sfl/cli/mode_handlers/gui_handler.rb` is **deleted**.
  - `lib/sfl/cli/commands/review_command.rb` is **deleted** (or repurposed without `--gui` support).
  - `exe/sfl-review` is **deleted**.
  - The `--gui` flag **no longer exists** for any subcommand (prints the same "unknown flag" error as any other unknown flag).
  - `lib/sfl/gui/review_queue_app.rb` remains but is **orphaned** (no entry point references it).

**Integration points**

- Delete `lib/sfl/cli/mode_handlers/gui_handler.rb`.
- Remove `--gui` support from `lib/sfl/cli/entry_point.rb` mode detection.
- Delete `exe/sfl-review`.
- Update `ecosystem-architecture.md` §4.1 to mark this as **done**.

**Definition of done**:
- `bundle exec exe/sfl-engine review --gui` prints "Unknown flag: --gui".
- `ls exe/sfl-review` fails (file not found).
- RuboCop clean.

---

### SFL-CLI-12 — DB maintenance rake tasks

**Points**: 3 · **Depends on**: none · **Epic**: E7

> **As a** maintainer
> **I want** `rake` tasks for pruning stale database entries and running migrations
> **so that** routine database upkeep is scripted and repeatable instead of manual/ad hoc (per §1.2 item 7).

**Acceptance criteria**

- **Given** `rake -T`, **then** it lists a `db` namespace with at least `db:prune` (removes stale/expired entries older than a configurable retention window) and `db:migrate` (runs pending Sequel migrations).
- **Given** `bundle exec rake db:prune`, **then** it deletes rows older than the configured retention window from the relevant tables and prints a summary count of rows removed.
- **Given** `bundle exec rake db:prune RETENTION_DAYS=7`, **then** it uses the given retention window instead of the default.
- **Given** `bundle exec rake db:migrate`, **then** it applies any pending Sequel migrations and is idempotent (a second run does nothing and exits 0).
- **Given** `lib/tasks/db.rake` (or equivalent), **when** grepped, **then** each task requires only the existing Sequel/pgvector connection setup — no new gem.

**Integration points**

- New file `lib/tasks/db.rake` (or `Rakefile` addition) defining the `db` namespace.
- Reuses the existing Sequel connection/config already used by the app; no new database adapter.

**Definition of done**:
- `bundle exec rake -T` shows `db:prune` and `db:migrate` with descriptions.
- `spec/tasks/db_rake_spec.rb` (or a Rake-task test harness) covers `db:prune`'s retention-window behavior.
- RuboCop clean.

---

## 6. Open Questions

### Q1 — Should `sfl-engine` be installed as a gem with binstubs, or remain a checkout-only script?

**Current state**: `sfl-engine` is **not** a gem (no `sfl-engine.gemspec`, no `gem install sfl-engine`). It is run as `bundle exec exe/sfl-analyze` from a checkout.

**Pros of gem installation**:
- Users can `gem install sfl-engine` and run `sfl-engine ingest ...` globally.
- Symlinks/aliases become unnecessary.

**Cons of gem installation**:
- The project has **no gemspec** and explicitly rejected one (see `README.md` and AGENTS.md).
- Zeitwerk autoloading, Docker service checks, and Python sidecar management assume a checkout with `lib/`, `app/`, `sidecar/` present.
- The Gemfile declares many development-only gems (`pry`, `rubocop`, `rspec`) that would bloat a gem installation.

**Tentative decision**: **Remain checkout-only.** The project's existing architecture assumes a checkout (e.g., `sidecar/spacy_sidecar.py` is a relative path, `SFL::DockerServices` checks for `docker compose` on PATH). A gem would need significant refactoring to support both modes. The symlink aliases (SFL-CLI-10) provide the convenience without the complexity.

**Resolution target**: Phase 1 gate.

---

### Q2 — Should subcommands support both `--tui` and individual subcommands like `sfl-engine tui`?

**Current design**: Mode flags only (`--tui`, `--gui`). The old `sfl-engine tui` subcommand is **not** implemented.

**Alternative**: Support both `sfl-engine ingest --tui` (mode flag) and `sfl-engine tui` (legacy subcommand) for backward compatibility.

**Tentative decision**: **Mode flags only.** Having both would create two paths to the same functionality, increasing maintenance burden. Users of `sfl-tui` should migrate to `sfl-engine ingest --tui`; since the old binstubs are deleted outright (SFL-CLI-09, no deprecation period), there is no legacy `sfl-engine tui` subcommand to keep around either.

**Resolution target**: Phase 1 gate.

---

### Q3 — How should TUI/GUI forms be generated from command parameter schemas?

**Approach 1**: Each command defines a `parameter_schema` method returning structured metadata (required/optional params, types, descriptions) that TUI/GUI handlers use to build forms.

**Approach 2**: Extract parameter definitions into shared YAML/JSON configs that both CLI parsing and mode handlers consume.

**Tentative decision**: **Approach 1 (programmatic schema).** Keeps everything in Ruby, type-safe, and co-located with command logic. The schema is simple enough (param name, type, required flag, description) to define inline in each command class.

---

## 7. Cross-references

| Reference | Relevance |
|---|---|
| [`ecosystem-architecture.md` §3.1](../ecosystem-architecture.md#31-shape) | The target-state diagram showing SCC as a driving adapter; this doc applies the same principle with **mode flags** (`--tui`, `--gui`) for interface switching. |
| [`ecosystem-architecture.md` §4.1](../ecosystem-architecture.md#41-the-fourth-mode--a-decision-to-make) | Explicit recommendation to retire `exe/sfl-review` — this doc implements that retirement via SFL-CLI-11 (removing `--gui` mode flag). |
| [`ecosystem-architecture.md` §6.1](../ecosystem-architecture.md#61-integration-contract) | The HTTP API contract that `ApiCommand` exposes via Roda/Falcon. |
| [SFL-ING-19](INGEST-PARSER-HEXAGON-USER-STORIES.md) | `TargetResolver` — precedent for runtime resolution by name; superseded here by Thor's own command lookup, but still the model for `Commands::*` argument resolution. |
| `track-ecosystem-architecture-engine-visual-driver-1odobii` | This doc's durable record on the sfl-engine side. |

---

## 8. Revision History

| Date | Change | Author |
|---|---|---|
| 2026-09-13 | **Reimagined architecture based on Plannotator feedback** — Replaced adapter-per-mode design with mode-flag pattern (`--tui`, `--gui`). Adapters retired in favor of mode handlers that wrap command implementations. Subcommands now accept mode flags to switch interfaces. See Revision Note at top of document. | Plannotator annotation |
| 2026-09-13 | **Retired the `analyze` subcommand** per Plannotator feedback on §2.2 — `ingest` becomes the full pipeline (ingest, embeddings, analyze, synthesize); `context` is renamed `query` and absorbs analyze's retrieve step with fine-grained flags/args. `AnalyzeCommand`/`ContextCommand` become `IngestCommand`/`QueryCommand`; former story SFL-CLI-04 merged into SFL-CLI-03. | Plannotator annotation |
| 2026-09-13 | **Replaced the single default subcommand with an interactive multi-select menu** — with no subcommand given (or `-`), `sfl-engine` now prompts the user to pick from the registered subcommands instead of silently running `ingest`. No subcommand is "default" anymore; `EntryPoint.prompt_subcommand` (§2.3) implements the menu. Updated SFL-CLI-01 and SFL-CLI-08 acceptance criteria accordingly. | Plannotator annotation |
| 2026-09-13 | **Overhauled subcommand dispatch to use `thor`** (already a Gemfile dependency alongside Roda), replacing the hand-rolled `Core::Registry`-based `EntryPoint`. `SFL::CLI::EntryPoint` is now a `Thor` subclass; each subcommand is a Thor command method; a new `SFL::CLI::Dispatch` module handles shared `--tui`/`--gui` detection. SFL-CLI-01 and §2.1/§2.3 rewritten; the `EMBEDDING-HEXAGON-USER-STORIES.md`/`SFL-EMB-01` `Core::Registry` cross-references are removed as no longer applicable. | Plannotator annotation |
| 2026-09-13 | **Removed the deprecation-warning/phased-migration strategy** — this project has no releases yet, so there is no installed base to warn. §3 is retitled "Replacement Strategy"; `exe/sfl-analyze`, `exe/sfl-tui`, `exe/sfl-api` are now deleted outright in the same change that ships `exe/sfl-engine` (SFL-CLI-09, rewritten from "deprecation warnings" to "delete old binstubs"), with no warn-then-delegate shim. `exe/sfl-review`'s removal is unaffected — it is still gated on SCC review parity (a functional condition, not a deprecation window). Dropped the "sfl-analyze" row from the §1.1 "what already exists" table and the standalone commentary sentences under §2.2 per direct feedback. | Plannotator annotation |
| 2026-09-13 | **Added §1.2 item 7 and story SFL-CLI-12** for `rake` tasks covering routine database maintenance (pruning stale entries, running migrations) — a new Epic E7, independent of the CLI refactor phases. | Plannotator annotation |

---

## 8. File Disposition

| File | Verdict | Rationale |
|---|---|---|
| `exe/sfl-engine` | **NEW** | Unified entry point with mode flag support. |
| `exe/sfl-analyze` | **DELETED** | `analyze` subcommand retired; replaced outright by `sfl-engine ingest`. No deprecation shim (SFL-CLI-09). |
| `exe/sfl-tui` | **DELETED** | Replaced outright by `sfl-engine ingest --tui`. No deprecation shim (SFL-CLI-09). |
| `exe/sfl-api` | **DELETED** | Replaced outright by `sfl-engine api`. No deprecation shim (SFL-CLI-09). |
| `exe/sfl-review` | **UNCHANGED (then DELETED)** | Superseded by `sfl-engine review --gui`; deleted separately once SCC review parity is reached (SFL-CLI-11) — a functional gate, not a deprecation window. |
| `exe/sfl-engine-*` | **NEW (symlinks)** | Scripting-convenience symlinks. Not committed to git. |
| `lib/sfl/cli/entry_point.rb` | **NEW** | `SFL::CLI::EntryPoint < Thor` — subcommand dispatch with mode flag detection. |
| `lib/sfl/cli/dispatch.rb` | **NEW** | `SFL::CLI::Dispatch.run` — shared `--tui`/`--gui` detection used by every Thor command method. |
| `lib/sfl/cli/mode_handlers/` | **NEW** | Directory containing `base_handler.rb`, `tui_handler.rb`, `gui_handler.rb`. |
| `lib/sfl/cli/commands/` | **NEW** | Directory containing `ingest_command.rb` (full pipeline, replaces the retired `analyze_command.rb`), `query_command.rb` (renamed from `context_command.rb`), `api_command.rb`, `review_command.rb`. |
| `lib/sfl/cli.rb` | **UNCHANGED** | Logic extracted into command classes; not modified. |
| `lib/sfl/tui/app.rb` | **UNCHANGED** | Consumed by `TuiHandler`. |
| `lib/sfl/gui/review_queue_app.rb` | **UNCHANGED (then orphaned)** | Consumed by `GuiHandler` until SFL-CLI-11. |
| `config.ru` | **UNCHANGED** | Consumed by `ApiCommand`. |
| `app/sfl.rb` | **UNCHANGED** | Consumed by `ApiCommand` via Roda. |
| `spec/cli/entry_point_spec.rb` | **NEW** | Tests for SFL-CLI-01. |
| `spec/cli/dispatch_spec.rb` | **NEW** | Tests for `SFL::CLI::Dispatch.run` (mode detection), part of SFL-CLI-01. |
| `spec/cli/mode_handlers/tui_handler_spec.rb` | **NEW** | Tests for SFL-CLI-02. |
| `spec/cli/mode_handlers/gui_handler_spec.rb` | **NEW (then DELETED)** | Tests for SFL-CLI-02. Deleted in SFL-CLI-11. |
| `spec/cli/commands/ingest_command_spec.rb` | **NEW** | Tests for SFL-CLI-03 (full pipeline, replaces the retired `analyze_command_spec.rb`). |
| `spec/cli/commands/query_command_spec.rb` | **NEW** | Tests for SFL-CLI-05 (renamed from `context_command_spec.rb`). |
| `spec/cli/commands/api_command_spec.rb` | **NEW** | Tests for SFL-CLI-06. |
| `spec/cli/commands/review_command_spec.rb` | **NEW (then DELETED)** | Tests for SFL-CLI-07. Deleted in SFL-CLI-11. |
| `spec/cli/sfl_engine_spec.rb` | **NEW** | Tests for SFL-CLI-08. |
| `.gitignore` | **MODIFIED** | Add `/exe/sfl-engine-*` entry. |
| `lib/tasks/db.rake` | **NEW** | `db:prune`/`db:migrate` rake tasks (SFL-CLI-12). |
| `spec/tasks/db_rake_spec.rb` | **NEW** | Tests for SFL-CLI-12. |

---

## 9. Phased Path

| Phase | Gate | Stories |
|---|---|---|
| **Phase 0** | Doc accepted | This document + open questions resolved |
| **Phase 1** | `sfl-engine` works end-to-end and old binstubs are gone | SFL-CLI-01, SFL-CLI-02, SFL-CLI-03, SFL-CLI-05, SFL-CLI-06, SFL-CLI-07, SFL-CLI-08, SFL-CLI-09 (delete `exe/sfl-analyze`, `exe/sfl-tui`, `exe/sfl-api` outright — no deprecation period), SFL-CLI-10 |
| **Phase 2** | GUI retired | SFL-CLI-11 (gated on SCC review parity — a functional gate, unrelated to Phase 1's binstub deletion) |
| **Independent** | DB maintenance scripted | SFL-CLI-12 (no dependency on the CLI refactor; can ship in any phase) |

---

## 10. Acceptance Test for the Whole Refactor

> **If a change makes a capability reachable only through a specific frontend, the change is wrong.**
> — Adapted from [`ecosystem-architecture.md` §4](../ecosystem-architecture.md#4-sfl-engine-stays-standalone--the-tri-mode-guarantee)

**Test matrix** (must all pass for CLI and TUI modes):

| Capability | `sfl-engine ingest` (CLI) | `sfl-engine ingest --tui` | `sfl-engine query` (CLI) | `sfl-engine query --tui` | `sfl-engine api` | `sfl-engine review --gui` (until retired) |
|---|---|---|---|---|---|---|
| Ingest conversation | ✅ | ✅ | ❌ | ❌ | ✅ (POST /ingest) | ❌ |
| Ingest documentation | ✅ | ✅ | ❌ | ❌ | ✅ (POST /ingest) | ❌ |
| Ingest knowledge-base | ✅ | ✅ | ❌ | ❌ | ✅ (POST /ingest) | ❌ |
| Retrieve / context query | ❌ | ❌ | ✅ | ✅ | ✅ (POST /retrieve) | ❌ |
| Review queue | ✅ (`review` subcommand) | ❌ | ❌ | ❌ | ✅ (GET /review-queue) | ✅ |
| Synthesis | ✅ (part of the full pipeline) | ✅ | ❌ | ❌ | ✅ (POST /synthesize) | ❌ |
| Pipeline compile | ✅ (`pipeline compile` subcommand) | ✅ | ❌ | ❌ | ✅ (POST /pipeline/compile) | ❌ |
| Topic modeling | ✅ (`--topics N` flag) | ✅ | ❌ | ❌ | ❌ | ❌ |

**Key**: ✅ = supported, ❌ = not applicable for that mode/subcommand.

**Invariant 1**: Every ✅ in the CLI column must also have a ✅ in the `api` column (or vice versa for capabilities that are API-only). This ensures the CLI and HTTP modes remain at feature parity.

**Invariant 2**: For every subcommand that supports `--tui`, the TUI mode must expose the **exact same parameters** as the CLI mode, with CLI-provided values taking precedence.

**Invariant 3**: The `--tui` and `--gui` flags work consistently across all subcommands that support them (all except `api`).
