# AGENTS.md — SFL Engine

## Project Overview

**Stance-Filtered RAG for LLM Security** — a Ruby application that hardens RAG pipelines against context poisoning by separating *what was said* from *how it was said*, then filtering the *how* before it reaches the LLM.

Non-gem single application (no gemspec, no `gem install`; clone and run). See `README.md` for the architectural vision and `rebuild-blueprint-with-plugin.md` for the full SIFT audit and phased backlog.

## Critical Architecture Facts

- **Zeitwerk autoloader** rooted at `lib/` (see `lib/sfl.rb`): one `SFL.loader` setup at require-time
- **`SFL::Boot`** (lib/sfl/boot.rb): sole ENV reader; all other classes take config via constructor injection
- **Pass 1**: spaCy subprocess sidecar (no in-process Python; track decision 2)
- **Pass 2**: ruby_llm-based annotation (replaces DSPy; track decision 7)
- **Storage**: Postgres/pgvector via Sequel (track decision 5: no auto-migration — run `rake db:migrate` manually)
- **GUI**: glimmer-dsl-libui (opt-in require; ignored by Zeitwerk, see `lib/sfl.rb:40`)
- **HTTP API**: Falcon server via `exe/sfl-api` → `config.ru`
- **CLI**: `exe/sfl-analyze` with subcommands (conversation, documentation, knowledge-base, context)

## Directory Layout

```
lib/sfl/
├── core/      # types, ports, pass1 sidecar, pipeline, loaders
├── store/     # Sequel/pg/pgvector repositories, migrations, retrieval
├── llm/       # ruby_llm + ruby_llm-schema annotators, per-task config
├── prompts/   # plain folder of prompt templates
├── cli/       # non-interactive/scriptable analyzer commands
├── gui/       # glimmer-dsl-libui desktop GUI (opt-in require)
└── chat/      # interactive chatbot agent (RubyLLM::Tool wrappers)
```

`experiments/` is quarantined — never autoloaded, never shipped.

## Developer Commands

```bash
# Full verification (default rake task)
bundle exec rake          # runs spec + rubocop

# Individual verification
bundle exec rspec                          # all specs
bundle exec rspec spec/path/to/file.rb     # single file
bundle exec rspec spec/path/to/file.rb:42  # single example
bundle exec rubocop                        # linter only
bundle exec rubocop --auto-correct         # auto-fix

# Database
rake db:migrate                     # run pending Sequel migrations
rake embeddings:redrive             # re-drive pending/failed embeddings

# Server
bundle exec exe/sfl-api             # starts Falcon on port 3001 (default), 0.0.0.0 by default (#33)
PORT=3002 bundle exec exe/sfl-api   # custom port
# NOT `bundle exec sfl-api` -- no gemspec/executables list (track decision 1), so there is no
# binstub for Bundler to resolve that bare command name to (live-verified 2026-08-02, #34).

# Setup
bin/setup-python                    # vendor spaCy into .sfl-python/
bin/setup-config                    # interactive .env setup wizard
```

## Key Conventions

### Ruby Version
- `.ruby-version` / `.tool-versions`: 4.0.1 (production target — issue #4)
- `.rubocop.yml`: `TargetRubyVersion: 4.0`
- Hash value omission (`{ turn_id:, total: }`) and anonymous `**` forwarding are valid syntax

### Code Style
- `frozen_string_literal: true` in every file (enforced by RuboCop)
- Double quotes for strings (`Style/StringLiterals: double_quotes`)
- 2-space indentation (enforced)
- Shopify-style RuboCop config (plugins: rubocop-shopify, rubocop-performance, rubocop-rspec, etc.)

### Testing
- RSpec with `--require spec_helper --format documentation --color`
- SimpleCov enabled (branch coverage, skips spec/ dir)
- `spec/examples.txt` persists example status (for `--only-failures`)
- Relaxed cops: `RSpec/MultipleExpectations: Max: 10`, `RSpec/ExampleLength: Max: 20`
- Shared examples in `spec/support/shared_examples/`

### ENV Loading
- `.env` loaded by `Dotenv.load` inside `SFL::Boot.call` (never at require-time)
- API keys: `OPENROUTER_API_KEY`, `GOOGLE_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `MISTRAL_API_KEY`
- Database: `DATABASE_URL=postgresql://sfl:sfl@localhost:5433/sfl_engine_dev`
- Per-task LLM config: `SFL_TASK_<TASK_NAME>_MODEL` / `_PROVIDER` / `_TEMPERATURE`

## Docker Services

`docker-compose.yml` provides Postgres (port 5433) and Redis (port 6380). `SFL::DockerServices.ensure_running!` (called from `exe/sfl-analyze` and `config.ru`) starts them only when `SFL_AUTO_START_DOCKER=1` is set (issue #17 — auto-start used to be unconditional, which fought an external `DATABASE_URL`); otherwise run `docker compose up -d` yourself.

## Gotchas

- **No auto-migration**: Boot never runs migrations; always `rake db:migrate` first on fresh DB
- **Pass 1 requires spaCy**: Run `bin/setup-python` to vendor; without it, Pass 1 sidecar fails loudly
- **Langfuse tracing**: Prompted interactively if `LANGFUSE_*` set but unreachable; use `--disable-tracing` to skip
- **Timezones**: `SFL_BATCH_SIZE` and other ENV vars must be set before `Dotenv.load` (Boot reads at call-time, not require-time)
- **Zeitwerk inflections**: Custom inflections in `lib/sfl.rb:12-28` — don't add files relying on default camelizing without checking

## Existing Instruction Files

- `README.md`: Architectural vision — the interdisciplinary synthesis (SFL, CBT, neuroscience, philosophy, Unix, cybersecurity)
- `rebuild-blueprint-with-plugin.md`: Full SIFT audit and phased backlog
- `docs/architectural-lineage.md`: The intellectual foundations — how each domain maps to engineering patterns
- `docs/use-cases/llm-role-isolation.md`: The Rhetorical Firewall hypothesis
- `ROADMAP.md`: Future phases (Rolling Synthesis, Cognitive Gas, Semantic Convergence)
- `.rubocop.yml`: Comprehensive RuboCop config (Shopify-style)
- `.rspec`: RSpec defaults
- `.env`: Environment variable documentation

## Per-Task LLM Configuration

| Task | ENV Prefix | Default Provider | Default Model |
|------|-----------|------------------|---------------|
| pass_two_annotation | `SFL_TASK_PASS_TWO_ANNOTATION_` | openrouter | mistralai/mistral-small-3.2-24b-instruct |
| pass_two_batch_annotation | `SFL_TASK_PASS_TWO_BATCH_ANNOTATION_` | openrouter | mistralai/mistral-small-3.2-24b-instruct |
| context_synthesis | `SFL_TASK_CONTEXT_SYNTHESIS_` | (inherits from pass_two_annotation) | (inherits) |
| embedding | `SFL_TASK_EMBEDDING_` | ollama | embeddinggemma:latest |
