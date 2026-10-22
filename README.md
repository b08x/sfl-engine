# SFL Engine

SFL Engine is a Ruby application that annotates text with Systemic Functional Linguistics (SFL) metadata and uses that metadata when retrieving text for an LLM.

## Purpose

The engine splits each clause of an input text into two parts:

- Ideational payload: what happened (processes, participants, circumstances).
- Interpersonal payload: how it is presented (mood, modality, tenor, attitude).

The two parts are stored separately. Retrieval can filter clauses by their interpersonal values before text is passed to an LLM.

## Main concepts

- Pass 1: syntactic parsing that finds clauses, process types, participants and circumstances.
- Pass 2: LLM annotation of mood, modality, tenor and attitude. The model is set per task through `SFL_TASK_*` variables.
- Store: Postgres with pgvector holds the clauses, embeddings and review queues.
- Retrieval: hybrid retrieval over the store, followed by context synthesis.
- Analysis: engines and scorers that run over conversations, documentation and knowledge bases.
- Eval: Langfuse datasets and a runner for unseen conversations.

## Glossary

- Collection: a named group of documents.
- Document: one whole item, such as a paper, a transcript or one chat conversation.
- Section: a segment of a document, such as a heading block or one speaker turn. Identified by `section_id`, for example `notes-3f9a1c2e#turn-3`. A file loader's prefix before `#` is the basename plus the first 8 hex digits of the SHA-256 of the file path (`Core::Loaders::FileId`), so two files with the same basename get different section ids and re-ingesting a file keeps its ids. A section id that is already stored under another document is refused with `SectionRegistry::ConflictError`. In a knowledge-base ingest, `KnowledgeBaseSource` skips only the conflicting unit, prints a warning, and stores the file's other units. In a conversation or documentation ingest, the error stops that file and ingest records it as a `draft_failed` review entry; units stored before the conflict stay stored. `ingest` expands `<path>` to an absolute path, so `notes`, `./notes` and `/abs/notes` give the same document key and section ids, and re-ingesting under any spelling replaces the document's sections and clauses.
- Clause: what annotation produces from a section. Each clause row carries the `section_id` of its section.

## Collections, documents, sections and runs

- `sfl-analyze ingest --collection NAME <path>` stores clauses and records each document and section in collection NAME. The collection is created when it does not exist. Without `--collection`, the name is the basename of `<path>`. `conversation --store` and `documentation --store` take the same option.
- Collection names are trimmed, keep their case and are unique ignoring case. An empty name is rejected.
- Tables: `collections`, `documents` (one row per `document_key`), `sections` (one row per `section_id`, nested through `parent_section_id`) and `runs`.
- Markdown and canvas sections nest by heading level. A heading is the parent of the sections that follow it until a heading of the same or a higher level. Turn sections have no parent, and their label is the speaker.
- Each conversation in a chat export file is one document; the export file is its source path.
- Ingesting a document whose key exists in another collection moves it, with its sections, and logs a `document moved` warning naming both collections. Re-ingesting into the same collection replaces its sections and clauses.
- Migration 016 puts clauses stored before collections existed into a collection named `legacy`: one document per section id prefix before `#`, one section per section id.
- `bundle exec rake db:purge_collection[NAME]` deletes a collection with its documents, sections and clauses and prints the counts.
- `bundle exec rake models:refresh` fills the `models` table from the `ruby_llm` registry and the Ollama and OpenRouter listings. A model missing from its provider's latest listing is marked unavailable; its row is kept. A provider whose listing fails is left unchanged, and the task exits non-zero.
- Stored runs (`ingest`, and `conversation`/`documentation` with `--store`) write one `runs` row keyed by `SFL_RUN_ID`, with kind, collection, status, total, done, failed, current item, pid and start, heartbeat and finish times. The heartbeat is written every 5 seconds. A running row whose heartbeat is older than 30 seconds is shown as stalled; one whose process no longer exists is shown as dead.

## Entry points

| Command | Purpose |
|---|---|
| `bundle exec exe/sfl-analyze` | CLI: `conversation`, `documentation`, `knowledge-base`, `ingest` and `context` subcommands |
| `bundle exec exe/sfl-api` | HTTP API server (default port 3001) |
| `bundle exec exe/sfl-tui` | Terminal UI: browse, review, select and export; search |

Run `exe/sfl-analyze --help` for options.

## Terminal UI

`exe/sfl-tui` is built on `ratatui_ruby`. It has four tabs, switched with `1` to `4`: Browse, Search, Runs and Models. Runs lists every run in the `runs` table (ingest, annotate, export, recompile), newest first, re-read every 2 seconds; stalled and dead runs are marked. Models lists each task with its effective provider and model and the source: `env`, `db` or `default`. A task's model is the `SFL_TASK_<TASK>_MODEL` variable when set (the row is locked and names the variable), else its `task_models` row, else the default. `Enter` on a task lists the models that have the capability the task needs (embedding for `embedding`, chat for the rest); `Enter` on a model saves it to `task_models`; `Esc` goes back; `r` refreshes the `models` table. A task whose assigned model is unavailable is marked `! unavailable`. Each run row records the effective model per task in its `models` column. `q` or Ctrl-C quits. The bottom line lists the keys of the current tab.

Browse shows collections, documents and nested sections on the left, the focused section's clauses in the middle and detail on the right.

- `↑`/`↓` move, `Tab` switches between the tree and the clause list, `Enter` expands or collapses a row.
- `f` cycles the status filter: all, pending review, accepted, rejected.
- A section with a pending content-review item shows `[R]`. Its detail shows the generated text, the reason and the source file. `A` approves, `R` rejects, `E` opens the text in `$VISUAL` or `$EDITOR`, recompiles the section (recorded as a `recompile` run) and records an edit. `o` shows an image item's source file. Inside kitty it is shown with `kitten icat` in an overlay window; press a key to return. Outside kitty it opens with `xdg-open`. Decisions are recorded under `SFL_REVIEWER_NAME`; without it they are refused.
- A clause with a pending annotation review shows `[A]`, and its detail shows the confidence. Annotation review is read-only here.
- `Space` selects the focused row and its descendants; a parent with only some descendants selected shows `[~]`. `a` selects every row at the current level, `Esc` clears. The status line shows the selected section and clause counts.
- `e` asks for a format (`j` JSONL, `m` Markdown) and writes the selected clauses, once each, in document and section order, to `<collection>-<timestamp>.jsonl|md` under `SFL_EXPORT_DIR` (default `./output/exports`). The export is recorded as an `export` run and its path is shown in the status line.

Search (`/` to type, `Enter` to run) uses the stored-clause retrieval and shows each hit's collection, document and section.

`i` opens the ingest launcher over any tab. It has three fields; `Tab` and `Shift-Tab` move between them:

- Path: the file or folder to ingest.
- Collection: an existing collection, chosen with `↑`/`↓`, or a new name. When it is empty, the collection is the path's base name.
- Flags: other `ingest` flags, `--output-dir DIR` and `--disable-tracing`. Unknown flags are refused.

`Enter` runs `exe/sfl-analyze ingest --collection NAME [flags] PATH` under a new `SFL_RUN_ID`; `Esc` closes the launcher. Inside kitty (`KITTY_WINDOW_ID` set and `KITTY_LISTEN_ON` reachable, which needs `allow_remote_control yes` and `listen_on` in `kitty.conf`) the ingest opens in a new kitty tab, where it draws its dashboard, and the tab stays open after it exits. Outside kitty, or when kitty refuses, the ingest runs as a detached child with its output in `SFL_INGEST_LOG_DIR/ingest-<run id>.log` (default `./output/logs`), and the TUI moves to the Runs tab, where the run appears.

## Setup

1. Start Postgres and Redis with `docker compose up -d`.
2. Copy `.env.example` to `.env` and set the values you need.
3. Apply migrations with `bundle exec rake db:migrate`. `sfl-tui`, `sfl-analyze ingest` and `--store` runs exit with the current and latest schema versions when this step is missing.

`SFL::Boot` loads `.env`. With `SFL_AUTO_START_DOCKER=1` in the shell environment, the `exe/` scripts start the Docker services when they are not running.

## Test

```
bundle exec rake
```

The default task runs RSpec, RuboCop and the Zeitwerk check.

## Logging

Logging is configured with environment variables. See `.env.example`.

- `SFL_LOG_TARGET` is a comma-separated list of targets: `stderr`, `journald`. The default is `stderr`.
- Every log call is written to every listed target.
- An unknown target name raises `Boot::Error`.
- If `journald` is listed and `/run/systemd/journal/socket` is missing, startup raises `Boot::Error`. There is no fallback to stderr. In the Docker `app` profile, mount the socket into the container.
- `SFL_LOG_LEVEL` sets the minimum level: `debug`, `info`, `warn`, `error` or `fatal`.
- `SFL_RUN_ID` is attached to every log line. It is shown as `run_id=...` on stderr and as the `SFL_RUN_ID` field in journald. When it is unset, a new id is generated per process.
- `rake eval:run_unseen` sets one run id per item.
- On a terminal, a foreground ingest or annotation run shows a full-screen dashboard: run id, collection, models per task, elapsed time, ingest and annotation progress, the log, and Ctrl-C for a graceful stop. The final screen stays until a key is pressed.
- When stdout or stderr is not a terminal, the CLI writes `progress turn=N total=M` to stderr after each finished turn, regardless of `SFL_LOG_TARGET`.

Examples:

```
SFL_LOG_TARGET=stderr,journald bundle exec exe/sfl-analyze conversation input.jsonl
journalctl SFL_RUN_ID=<id>
```

## Eval tasks

- `rake eval:build_narrative_dataset` loads the narrative digests into Langfuse.
- `rake eval:setup_langfuse` creates score configs and annotation queues.
- `rake eval:run_unseen` runs Pass 2 on unseen conversations and writes `output/eval/nd-<n>/`.

## Directory layout

```
exe/             executables
lib/sfl/boot.rb  configuration and wiring (only code that accesses ENV)
lib/sfl/core/    types, ports, Pass 1, pipeline, loaders
lib/sfl/llm/     LLM engines, signatures, model configuration
lib/sfl/store/   Sequel repositories for Postgres and pgvector
lib/sfl/retrieval/  context synthesis
lib/sfl/analysis/   analysis engines and sources
lib/sfl/ingest/  input loaders
lib/sfl/formatters/ output formatters
lib/sfl/eval/    Langfuse client and eval runner
lib/sfl/api/     HTTP API
lib/sfl/cli/     CLI helpers (progress bars, stop flag)
lib/sfl/tui/     terminal UI (ratatui_ruby)
lib/sfl/export/  JSONL and Markdown export of selected clauses
rakelib/         rake tasks
spec/            RSpec specs
docker/          Dockerfile and database init script
```
