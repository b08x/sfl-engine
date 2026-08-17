# AGENTS.md — SFL Engine

## Project Overview

**Stance-Filtered RAG for LLM Security** — a Ruby application that hardens RAG pipelines against context poisoning by separating *what was said* from *how it was said*, then filtering the *how* before it reaches the LLM.

Non-gem single application (no gemspec, no `gem install`; clone and run). See `README.md` for the architectural vision and `rebuild-blueprint-with-plugin.md` for the full SIFT audit and phased backlog.

## Critical Architecture Facts

- **Zeitwerk autoloader** rooted at `lib/` (see `lib/sfl.rb`): one `SFL.loader` setup at require-time; `lib/sfl/gui` is ignored and opt-in.
- **`SFL::Boot`** (`lib/sfl/boot.rb`) is the sole ENV reader; other classes take config via constructor injection.
- **Pass 1** is a spaCy subprocess sidecar (no in-process Python); **Pass 2** uses dspy.rb annotation.
- **Storage** is Postgres/pgvector via Sequel; migrations are never automatic.
- **HTTP API**: Falcon via `exe/sfl-api` → `config.ru`. **CLI**: `exe/sfl-analyze` subcommands conversation, documentation, knowledge-base, context.

## Directory Layout

```
lib/sfl/{core,store,llm,analysis,cli,gui,chat}/
# core: types, ports, sidecar, pipeline, loaders
# store: Sequel/pg/pgvector repositories, migrations, retrieval
# llm: dspy.rb annotators and per-task config
# cli/gui/chat: scriptable CLI, opt-in desktop GUI, interactive agent
```

`experiments/` is quarantined — never autoloaded or shipped.

## Developer Commands

```bash
# Prerequisites and local services
docker compose up -d                 # Postgres 5433, Redis 6380
bin/setup-python                     # vendor spaCy into .sfl-python/
bin/setup-config                     # interactive .env wizard

# Full verification (Rakefile default: spec + rubocop + Zeitwerk check)
bundle exec rake
bundle exec rspec                     # all specs
bundle exec rspec spec/path/to/file.rb
bundle exec rspec spec/path/to/file.rb:42
bundle exec rubocop
bundle exec rubocop --auto-correct

# Database (explicit; Boot never migrates)
bundle exec rake db:migrate
bundle exec rake embeddings:redrive
bundle exec rake zeitwerk:check

# CLI and API
bundle exec exe/sfl-analyze conversation input.jsonl --store
bundle exec exe/sfl-analyze documentation ./docs/ --store
bundle exec exe/sfl-analyze context "what happened?" --limit 10
bundle exec exe/sfl-api                 # Falcon on 0.0.0.0:3001
PORT=3002 bundle exec exe/sfl-api
HOST=localhost bundle exec exe/sfl-api  # loopback bind
```

Do not use `bundle exec sfl-analyze` or `bundle exec sfl-api`: this checkout has no gemspec/executables list; run the `exe/` scripts directly. Containerized API commands are `docker compose --profile app build api`, `docker compose --profile app up -d api`, and `docker compose --profile app run --rm migrate`.

## Key Conventions

- `.ruby-version` pins **4.0.1**; `.tool-versions` currently says **Ruby 4.0.4**. `.rubocop.yml` targets Ruby 4.0; resolve the version-file discrepancy before changing toolchain assumptions.
- Every Ruby file has `# frozen_string_literal: true`; use double-quoted strings and 2-space indentation. Shopify-style RuboCop plugins are enabled.
- Hash value omission (`{ turn_id:, total: }`) and anonymous `**` forwarding are valid syntax.
- Keep Zeitwerk paths/names aligned; custom inflections live in `lib/sfl.rb:8-29`.

## Testing and Configuration

- `.rspec` loads `spec_helper`, uses documentation format and color. SimpleCov branch coverage is enabled; `spec/examples.txt` persists example status.
- Shared examples live in `spec/support/shared_examples/`; RuboCop relaxes `RSpec/MultipleExpectations` to 10 and `RSpec/ExampleLength` to 20.
- `.env` is loaded by `Dotenv.load` inside `SFL::Boot.call`, never at require-time. Use `.env.example` as the documented template; do not print or commit secrets.
- Configure `DATABASE_URL` for Postgres (Compose uses port 5433), `SFL_TASK_<TASK_NAME>_MODEL`, `_PROVIDER`, and `_TEMPERATURE`; API keys include `OPENROUTER_API_KEY`, `GOOGLE_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, and `MISTRAL_API_KEY`.

## Gotchas

- Fresh databases require `bundle exec rake db:migrate`; `docker compose up -d` starts only Postgres/Redis. App services require `--profile app`.
- Pass 1 requires `bin/setup-python`; without the sidecar it fails loudly.
- `SFL_AUTO_START_DOCKER=1` is an explicit opt-in for CLI/API Docker auto-start; otherwise start services manually.
- Langfuse tracing can prompt when configured but unreachable; use CLI `--disable-tracing` to skip it. ENV must be set before `Dotenv.load` (Boot reads at call-time).

## Existing Instruction Files

`README.md` (architecture and usage), `rebuild-blueprint-with-plugin.md` (SIFT backlog), `docs/` (lineage, use cases, assessments), `ROADMAP.md`, `.rubocop.yml`, `.rspec`, `.env.example`, and `docker-compose.yml`.

## Per-Task LLM Configuration

| Task | ENV Prefix | Default |
|------|-----------|---------|
| Pass 2 annotation / batch | `SFL_TASK_PASS_TWO_ANNOTATION_` / `SFL_TASK_PASS_TWO_BATCH_ANNOTATION_` | openrouter / `mistralai/mistral-small-3.2-24b-instruct` |
| Context synthesis | `SFL_TASK_CONTEXT_SYNTHESIS_` | inherits Pass 2 |
| Embedding | `SFL_TASK_EMBEDDING_` | ollama / `embeddinggemma:latest` |
