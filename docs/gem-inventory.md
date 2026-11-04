# Gem inventory

What every direct dependency in the `Gemfile` does in this project — and
which ones do nothing. Written as an audit, not a brochure: every *Used*
row cites a call site (`file:line`), and every *Not used* verdict is a
bounded negative claim: the search covered `lib/`, `exe/`, `bin/`,
`rakelib/`, `spec/` and `app/` for requires and call-site constants. A gem
wired dynamically or through `Bundler.require` auto-loading outside those
trees would promote a *Not used* row to *Used*; nothing else would.

Verified against the `development` branch at commit `d974b45`
(2026-10-23), Ruby 4.0.1, by grep-and-read — one usage trace over the
codebase plus two follow-up greps for the TTY trio. The `Gemfile`'s own
section comments were treated as claims to check, not facts to copy;
where a comment and the code disagree, the table says so.

Updated against `fbb5ed0` (2026-10-24): the `dspy`, `dspy-o11y-langfuse`,
`ruby_llm` and `ruby_llm-template` rows now track the RubyLLM narrator
migration (`52ed0ac`), and the `docker-api`, `bake`, `decode` and
`rubydex` rows — four `Gemfile` entries the `d974b45` pass left
uncovered — were added in the same update.

## The table

### Core infrastructure

| Gem | What it does here | Evidence |
|---|---|---|
| `zeitwerk` | Autoloader for all of `lib/`; file names must match constant names, enforced by the rake Zeitwerk check | `AGENTS.md` conventions; `bundle exec rake` gate |
| `json` (~> 2.21) | JSON parsing; pinned below 3.0 because json 3.0 removed `create_additions`, which Sequel's `parse_json` still calls — un-pinned, every jsonb-column read raises `ArgumentError` | `Gemfile` pin comment |
| `dotenv` | Loads `.env`; read only by `SFL::Boot`, never at require time | `Gemfile` comment; `lib/sfl/boot.rb` |
| `dry-monads` | `Result` monad for error paths in the registry, pipeline and TUI commands (`SafeCommand`) | `lib/sfl/core/registry.rb:18` |
| `dry-struct` | Typed value objects — ~20 struct types (Participant, SyntacticToken, refs) | `lib/sfl/core/types/participant.rb:7` |
| `dry-types` | Type definitions (`Types::String` etc.) backing every struct attribute | `lib/sfl/core/types.rb:16` |
| `sorbet-runtime` | `T::Struct`/`T::Enum` for LLM signature value objects; serialized by `ResponseSymbolizer` | `lib/sfl/llm/signatures/clause_annotation_signature.rb:22` |
| `amatch` | Jaro-Winkler fuzzy matching for classification and digest-grounding checks | `lib/sfl/core/classification_registry.rb:182` |

### LLM annotation (Pass 2)

| Gem | What it does here | Evidence |
|---|---|---|
| `dspy` | The LLM framework for Pass 2 annotation and the loader-drafting predictor: Predict/ChainOfThought programs over `lib/sfl/llm/signatures/` (the narrative signatures are no longer run as DSPy programs — the RubyLLM narrator reuses only their description text) | `lib/sfl/ingest/loader_drafter.rb:4` |
| `dspy-anthropic` | Provider integration for DSPy (Anthropic) | `Gemfile` section; DSPy provider setup |
| `dspy-openai` | Provider integration for DSPy (OpenAI-compatible) | `Gemfile` section; DSPy provider setup |
| `dspy-o11y` | Observability layer for DSPy | `lib/sfl/llm/tracing.rb` |
| `dspy-o11y-langfuse` | Langfuse tracing of every LLM call through DSPy (`DSPy::Observability.configure!(adapter: :langfuse)`) — the RubyLLM narrator is outside this path | `lib/sfl/llm/tracing.rb:18` |
| `ruby_llm` | First-class LLM client for the narrative narrator — one chat call per narrative, sections parsed from plain text by `SectionParser`; the model catalog also reads its registry | `lib/sfl/llm/narrators/narrative_generator.rb:3`; `lib/sfl/llm/catalogs/ruby_llm_catalog.rb:17` |
| `ruby_llm-docker` | *Not used.* Docker orchestration shells out to `docker compose` directly | no call site |
| `ruby_llm-template` | *Not used.* The base `ruby_llm` gem **is** used — the narrator calls it directly and the model catalog reads its registry — but not through this wrapper | no call site; `lib/sfl/llm/narrators/narrative_generator.rb:3`; `lib/sfl/llm/catalogs/ruby_llm_catalog.rb:17` |

### Observability & logging

| Gem | What it does here | Evidence |
|---|---|---|
| `opentelemetry-sdk` | Export path for Langfuse tracing; `lib/` never requires OpenTelemetry directly — consumed only through `dspy-o11y-langfuse`, exactly as the `Gemfile` comment claims | `lib/sfl/llm/tracing.rb:3`; `lib/sfl/core/ports/instrumenter.rb:8` |
| `opentelemetry-exporter-otlp` | OTLP exporter for the tracing above | same |
| `journald-logger` | The `journald` log target behind `SFL_LOG_TARGET` | `lib/sfl/core/ports/journald_logger.rb:20` |

### Source loaders

| Gem | What it does here | Evidence |
|---|---|---|
| `csv` | CSV parsing for `CsvSource` and the CSV output formatter | `lib/sfl/core/loaders/csv_source.rb:50` |
| `inkmark` | Markdown → heading-chunked sections for `MarkdownSource` | `lib/sfl/core/loaders/markdown_source.rb:88` |
| `pragmatic_tokenizer` | Prose tokenization for MarkdownSource and the topic modeler | `markdown_source.rb:162`; `topic_modeler.rb:337` |
| `yajl-ruby` | Streaming JSON/JSONL parsing for the chat-export and JSON sources | `lib/sfl/core/loaders/chatgpt_export_source.rb:42` |
| `json_canvas` | Obsidian `.canvas` node-graph parsing for `CanvasSource` | `lib/sfl/core/loaders/canvas_source.rb:50` |
| `kreuzberg` | PDF text extraction with sentence-aware chunking for `PdfSource` | `lib/sfl/core/loaders/pdf_source.rb:44` |

### Analysis

| Gem | What it does here | Evidence |
|---|---|---|
| `tomoto` | LDA/HDP topic modeling pre-pass shared by every analysis source | `lib/sfl/analysis/topic_modeler.rb:294` |
| `lingua` | English readability scoring | `lib/sfl/analysis/readability_scorer.rb:14` |

### Retrieval

| Gem | What it does here | Evidence |
|---|---|---|
| `bm25f` | *Not used.* No BM25 code anywhere; retrieval is pgvector + SQL | no call site |
| `tf-idf-similarity` | *Not used.* | no call site |
| `schematist` | *Not used directly.* Transitive dep of `ruby_llm`; nothing in `lib/` calls it | `Gemfile.lock:436` |

### Storage

| Gem | What it does here | Evidence |
|---|---|---|
| `pg` | Postgres driver | `lib/sfl/store/` |
| `pgvector` | Vector-column encoding for pgvector embeddings | `lib/sfl/store/` |
| `sequel` | ORM: the repositories for documents, sections, clauses, runs and review queues | `lib/sfl/store/` |

### HTTP API

| Gem | What it does here | Evidence |
|---|---|---|
| `falcon` | The Rack server `exe/sfl-api` runs under (async fibers, hence the store's concurrency design) | `exe/sfl-api:23`; `lib/sfl/store/database.rb:15` |
| `rack` | Request interface: static files, `Rack::Request` handling | `config.ru:8`; `lib/sfl/api/server.rb:68` |
| `roda` | The API app framework | `app/sfl.rb:3` |

### CLI UX

| Gem | What it does here | Evidence |
|---|---|---|
| `tty-progressbar` | *Not used.* The `Gemfile` comment claims it replaced print/puts; no require or call site exists. The CLI's actual progress is the stderr `progress` line and the dashboard | no call site; `README.md` Logging section |
| `tty-prompt` | Interactive `.env` setup wizard | `bin/setup-config:24` |
| `tty-spinner` | Spinner around LLM-driven dynamic format expansion | `lib/sfl/analysis/dynamic_format_expander.rb:118` |
| `informers` | *Not used.* A spec actually *forbids* requiring it; a goals doc notes "removing the unused informers gem" was deferred | `spec/core/registry_spec.rb:87` |

### TUI

| Gem | What it does here | Evidence |
|---|---|---|
| `ratatui_ruby` | The Rust ratatui wrapper behind `sfl-tui` (Browse, Search, Runs, Models tabs) | `README.md` Terminal UI; `lib/sfl/tui/` |

### Media / utilities

| Gem | What it does here | Evidence |
|---|---|---|
| `image_processing` | *Not used.* Image work goes through a vision-capable chat model, not Vips/MiniMagick | no call site |
| `algorithms` | *Not used.* | no call site |
| `terrapin` | *Not used.* External commands go through `TTY::Command` and plain `system` | no call site |
| `jsonl` | *Not used.* JSONL writing is hand-rolled on stdlib JSON; reading goes through Yajl | no call site; `lib/sfl/export/jsonl_writer.rb:19` |
| `pycall` | *Not used.* Legacy's PyCall wrappers were replaced by a Python sidecar over NDJSON; the gem survives only in "legacy did this" comments | no call site; `lib/sfl/core/pass_one/spacy_sidecar_parser.rb` |
| `ruby-spacy` | *Not used.* Same sidecar replacement (`sidecar/spacy_sidecar.py`) | no call site |
| `tree_sitter_language_pack` | *Not used.* Zero references anywhere | no call site |
| `rllama` | *Not used.* (Ollama "llama" strings in specs are model-family names, unrelated) | no call site |
| `tty-which` | *Not used.* Binary detection probes by hand | no call site |
| `tty-command` | Runs kitty remote-control commands in `KittyHost` (the TUI's launcher/image overlay) | `lib/sfl/core/ports/kitty_host.rb:44` |

### Development & test

| Gem | What it does here | Evidence |
|---|---|---|
| `pry` | Interactive debugging | convention |
| `pry-byebug` | Breakpoint debugging inside Pry | convention |
| `rack-test` | HTTP API request specs | `spec/app/` |
| `rake` | The default gate (`bundle exec rake`): specs, RuboCop, Zeitwerk check | `AGENTS.md` Commands |
| `rspec` | The spec suite; every `lib/` file has a mirrored spec | `AGENTS.md` Conventions |
| `cucumber` (~> 12.0) | Gherkin runner for `features/*.feature`, bundled so the external implementer/verifier gates can run it; the repo ships no step definitions | `Gemfile` comment; `AGENTS.md` Commands |
| `rubocop` (+ performance, rake, rspec, sequel, shopify, thread_safety plugins) | Lint gate over the codebase; excludes the draft quarantine on purpose | `.rubocop.yml`; `AGENTS.md` |
| `ruby-lsp` | Editor language-server tooling | convention |
| `solargraph` | Editor language-server tooling | convention |
| `docker-api` (~> 2.4) | Drives the docker socket through the gem's `Docker::` API to build and smoke-test the spaCy sidecar image — `bin/build-sidecar` runs no docker CLI commands | `bin/build-sidecar:16` (`require "docker"`); `Docker::Image.build_from_dir` at `bin/build-sidecar:72`; `Docker::Container.create` at `bin/build-sidecar:102` |
| `bake` (~> 0.25.0) | *Not used.* No require, no `Bake` constant, no `Bakefile`, no bake task in any tree; the introducing commit `0d7532a` calls it a "bake task runner", a claim the working tree does not support | no call site; `Gemfile:258` |
| `decode` (~> 0.30.0) | *Not used.* No require and no decode or `.yardopts` config; every code-tree `decode` hit is unrelated prose or the pgvector gem's own `Pgvector.decode` | no call site; `Gemfile:259` |
| `rubydex` (~> 0.4.2) | *Not used.* No require, no `Rubydex` constant, no `rdx` invocation in any quality gate, and no MCP launch config anywhere in the repo — the gem exists here as a `Gemfile` entry and a lockfile checksum | no call site; `Gemfile:260` |

### Quality

| Gem | What it does here | Evidence |
|---|---|---|
| `simplecov` | Coverage measurement | `:quality` group |
| `mutant-rspec` (~> 0.17.0) | Mutation-testing gate (`bundle exec mutant run --use rspec`) | `AGENTS.md` Commands |
| `bundler-audit` (~> 0.9.3) | `Gemfile.lock` vulnerability scan against ruby-advisory-db | `AGENTS.md` Commands |

### Performance

| Gem | What it does here | Evidence |
|---|---|---|
| `benchmark-ips` | Iteration benchmarks | `:perf` group |
| `memory_profiler` | Allocation profiling | `:perf` group |
| `stackprof` | Stack-sampling profiler | `:perf` group |

## Findings

**21 direct dependencies have no call site.** Of the 55 direct gems the
`Gemfile` declares, these exist only as `Gemfile` entries and
`Gemfile.lock` rows:

`bm25f`, `tf-idf-similarity`, `schematist`, `image_processing`,
`algorithms`, `terrapin`, `informers`, `jsonl`, `pycall`, `ruby-spacy`,
`tree_sitter_language_pack`, `rllama`, `tty-progressbar`, `tty-which`,
`ruby_llm-docker`, `ruby_llm-template`, `bake`, `decode`, `rubydex` —
and, by their nature, the `opentelemetry-*` pair, which is indirect
*by design* and documented as such.

Two complications for anyone pruning:

- `schematist` rides in as a dependency of `ruby_llm`, itself a direct
  `Gemfile` entry with two call sites — the narrator
  (`lib/sfl/llm/narrators/narrative_generator.rb:3`) and the model
  catalog (`lib/sfl/llm/catalogs/ruby_llm_catalog.rb:17`) — so removing
  `ruby_llm-template` from the `Gemfile` removes nothing either needs.
- `fiddle` stays in the lockfile only as a dependency of `pycall` and
  `ruby-spacy` (`spec/tui/consolidation_spec.rb:29`); removing those two
  gems changes what that spec asserts.

**One `Gemfile` comment contradicts the code.** `tty-progressbar`'s
comment claims it is "a real progress bar (turn/artifact completion +
ETA) replacing the old plain print/puts pair." No require of it exists;
the CLI's progress output is the `progress turn=N total=M` stderr line
and the full-screen dashboard. As far as the code shows, the comment
describes an intention the code never implemented.

Commit `0d7532a`'s message makes the same move for three more gems: it
introduces `bake` as a "bake task runner", `decode` for "decode-style
doc coverage" and `rubydex` for "rdx semantic lint / dead-code scans
used by the quality gates". The tree supports none of the three — no
require, no task, no gate touches them.

## Method

Every *Used* row cites a call site found by grepping for the gem's
require form and its constants, then reading the site. *Not used*
verdicts are scout-tier negative claims bounded by the search surface
named at the top of this document. Convention-tier rows (`pry`,
`ruby-lsp`, `solargraph`, `rake`, `rspec`) are not call-site-traced;
their job is to exist in the dev environment, and a usage grep would
promote them if anyone needs the proof.
