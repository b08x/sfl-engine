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

## Entry points

| Command | Purpose |
|---|---|
| `bundle exec exe/sfl-analyze` | CLI: `conversation`, `documentation`, `knowledge-base` and `context` subcommands |
| `bundle exec exe/sfl-api` | HTTP API server (default port 3001) |
| `bundle exec exe/sfl-tui` | Terminal UI |
| `bundle exec exe/sfl-review` | Desktop GUI for the review queue |

Run `exe/sfl-analyze --help` for options.

## Setup

1. Start Postgres and Redis with `docker compose up -d`.
2. Copy `.env.example` to `.env` and set the values you need.
3. Apply migrations with `bundle exec rake db:migrate`.

`SFL::Boot` loads `.env`. The `exe/` scripts start the Docker services when they are not running.

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
- The CLI writes `progress turn=N total=M` to stderr after each finished turn, regardless of `SFL_LOG_TARGET`.

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
lib/sfl/tui/     terminal UI
lib/sfl/gui/     desktop GUI
rakelib/         rake tasks
spec/            RSpec specs
docker/          Dockerfile and database init script
```
