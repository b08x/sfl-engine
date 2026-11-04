# SFL Engine

SFL Engine annotates text with Systemic Functional Linguistics (SFL) metadata and uses that metadata when retrieving text for an LLM. The mechanism fits in one sentence; the convictions behind it take a page, and the page is worth reading first, because they ground the storage and retrieval decisions that shape the operational sections below.

## Why this engine exists

The retrieval systems I have used answer *what is this text about?*. None I have tried exposes *how was it said?* as a filterable column — a claim about my inventory, not the field's: name one that does, and this paragraph narrows to an ergonomics argument. And by "how," I mean stance: whether a sentence asserts, hedges, instructs or worries; whether a speaker positions themselves above, below or alongside the listener; whether a claim is presented as a finding or offered as a guess. Vector similarity averages those distinctions away — a single embedding pools a clause's topic and its stance into one point, so a hedging and an asserting paraphrase can land close together — and I find that a real loss, because stance is the dimension I notice first when I read closely — a claim about this reader, not every reader.

The theory that names those distinctions is Systemic Functional Linguistics — Halliday's account of language as choice-in-context, in which one clause simultaneously does several kinds of work, its *metafunctions*: an **ideational** payload (what happened: processes, participants, circumstances) and an **interpersonal** payload (how it is presented: mood, modality, tenor, attitude). Halliday's theory also describes a third, *textual* metafunction; the engine's payload split leads with the two its retrieval hypothesis depends on. ("Metafunction" is a technical term, not a metaphor — it names the different kinds of meaning one clause carries at once.)

SFL has, in its published tradition — Halliday's An Introduction to Functional Grammar and its line of applications — been a close-reading framework for humans. This engine uses it the other way round: as a feature-extraction schema for machines. Annotation turns stance from something a prompt can *ask* a model to respect into something a query can *filter on* — and that difference is structural. A prompt instruction is a suggestion — no code path enforces it; a scalar filter that excludes a clause before the model's context is ever assembled is a guarantee (`pg_hybrid_retriever.rb:64`, `context_synthesizer.rb:46`) — of exclusion, not of annotation truth: the filter enforces what Pass 2 recorded, so a mislabeled clause is excluded by its mislabel, not by its stance. The engine's founding bet is that the second kind of defense is the one worth engineering — a bet with a named promotion condition: the day `rake eval:run_unseen` scores stance-filtered retrieval against prompt-only retrieval on the held-out set, the bet retires into a finding.

Two storage decisions follow from that bet:

- **Payload separation.** The ideational and interpersonal payloads do not share a table. Facts live in one table, tone in another — `ideational_payloads` and `interpersonal_payloads` (migrations 002/003). This is not normalization for its own sake; it is what makes "how was this said" a filterable dimension in its own right rather than a paraphrase of "what was said." Retrieval can filter clauses by their interpersonal values before any text reaches the LLM.
- **Clause-level units.** The unit of storage and retrieval is the clause, not a token-count chunk. A fixed-size chunk is a computational convenience; a clause is a complete unit of meaning — one process, its participants, its circumstances, one stance — so what gets retrieved is whole.

## Design principles

Each principle below is enforced somewhere checkable — a spec, a gate or a code path — noted inline.

1. **Defense is structural, not behavioral.** Retrieval filters run against stored metadata, before the model's context is assembled. A clause that fails the filter never enters the context window (`lib/sfl/store/pg_hybrid_retriever.rb:64`, `lib/sfl/retrieval/context_synthesizer.rb:46`).
2. **LLM output is untrusted data, never code.** When ingest meets a file shape no loader recognizes, the LLM's candidate loader is parsed (never `eval`'d), gated on three gates, and written into a quarantine directory the runtime never loads. Promotion into `lib/` is a human copy, never a code path. Incident `4a53727` — one bad draft dropped into the autoloaded tree, failing the whole test suite — is why this is a permanent constraint rather than a preference.
3. **One bad input never halts the run.** Ingest isolates failure per file: a file that fails is recorded in the review queue, and the rest of the run continues (`spec/ingest/orchestrator_spec.rb:191`).
4. **Degradation is truthful, never silently fudged.** An out-of-range annotation value is rejected by contract and degraded with recorded provenance, not rescaled to fit. Fallback annotations are marked as fallback and excluded from what retrieval can cite — a fallback should never silently ground an answer (the type contract constrains modality to 0.0–1.0, `lib/sfl/core/types/modality_weight.rb:11`).
5. **Determinism where rules work; models where semantics need them.** Pass 1 is deterministic syntactic parsing; Pass 2 is LLM annotation. Annotation provenance is recorded — a fallback value is marked as fallback — so a degraded value is never mistaken for a finding (`lib/sfl/llm/degradation.rb:24`).
6. **Citations are checked, not trusted.** The context synthesizer maps the model's citation numbers to real clause ids and drops the out-of-range ones (`lib/sfl/retrieval/context_synthesizer.rb:125`).
7. **Configuration flows one way.** `SFL::Boot` is the only code that reads `ENV`; every other class receives its configuration as injected arguments, and a spec fails on any other `ENV` read under `lib/`, `exe/` or `rakelib/`.
8. **Review is human and named.** Review decisions are refused without `SFL_REVIEWER_NAME`, and annotation review is read-only in the UI — the decision trail is not editable from the review screen (`lib/sfl/tui/browse/commands.rb:13`).
9. **Naming is vocabulary.** *Document*, *section* and *clause* mean specific things (see the Glossary), everywhere — code, specs, CLI output and docs; the check is convention and review, not a spec or a gate.
10. **Docs are audit, not brochure.** `docs/gem-inventory.md` records what every dependency does — and which ones do nothing — with cited call sites; documentation commits pin claims to verified behavior.

## How the engine works

The engine compiles text into annotated clauses in two passes with a hard boundary between them; the clauses then flow through storage, retrieval, analysis and evaluation:

- **Pass 1** — deterministic syntactic parsing that finds clauses, process types, participants and circumstances. It runs as a Python spaCy sidecar over NDJSON, behind a typed port, so the rest of the codebase never sees the transport and tests can swap in fakes. The pipeline composes the passes through a Result ladder: a Pass 1 failure short-circuits everything downstream for that unit (`lib/sfl/core/pipeline.rb:83`).
- **Pass 2** — LLM annotation of mood, modality, tenor and attitude, producing the interpersonal payload. The model is set per task through `SFL_TASK_*` variables. Batches are bounded at 40 (`DEFAULT_BATCH_SIZE`, `lib/sfl/llm/engine.rb:53`), and provider-side failures back off and retry (`lib/sfl/llm/engine.rb:36`) instead of filling the run with placeholders. Annotations are model output: requests can be pinned (temperature, seed, `spec/llm/request_pinning_spec.rb:13`), but a re-run is not promised to reproduce them; each run row records the model per task, so which run produced a stored value is answerable in one query.
- **Store** — Postgres with pgvector holds the clauses, their separated payloads, embeddings and review queues. One database, one place to filter and search; a section's clauses are replaced atomically in one transaction (`lib/sfl/store/pg_clause_store.rb:43`).
- **Retrieval** — hybrid retrieval (reciprocal-rank fusion over vector and lexical search, plus scalar filters over the stored metadata), followed by context synthesis that only cites clauses that exist.
- **Analysis** — the analysis engine and its named scorers and trackers — quality and readability scoring, cohesion, speaker profiles, tenor shifts, topics (`lib/sfl/analysis/`) — over conversations, documentation and knowledge bases.
- **Eval** — Langfuse datasets and a runner that annotates held-out conversations 11–14 (`rakelib/eval.rake:31`), *unseen* by the narrative dataset, on purpose.

Everything below this line is operational reference.

---

## Glossary

- Collection: a named group of documents.
- Document: one whole item, such as a paper, a transcript or one chat conversation.
- Section: a segment of a document, such as a heading block or one speaker turn. Identified by `section_id`, for example `notes-3f9a1c2e#turn-3` (id construction and conflict rules: see Collections, below).
- Clause: what annotation produces from a section. Each clause row carries the `section_id` of its section.

## Collections, documents, sections and runs

Storage is four nested records — collections hold documents, documents hold sections, sections hold clauses — and one `runs` row watches every write; the bullets below give that model in command order.

- `sfl-analyze ingest <path> --collection NAME` stores clauses and records each document and section in collection NAME. The collection is created when it does not exist. Without `--collection`, the name is the basename of `<path>`. `conversation --store` and `documentation --store` take the same option.
- **Section ids and conflicts.** A file loader's prefix before `#` is the basename plus the first 8 hex digits of the SHA-256 of the file path (`Core::Loaders::FileId`), so two files with the same basename get different section ids and re-ingesting a file keeps its ids. A section id that is already stored under another document is refused with `SectionRegistry::ConflictError`. In a knowledge-base ingest, `KnowledgeBaseSource` skips only the conflicting unit, prints a warning, and stores the file's other units. In a conversation or documentation ingest, the error stops that file and ingest records it as a `draft_failed` review entry; units stored before the conflict stay stored. `ingest` expands `<path>` to an absolute path, so `notes`, `./notes` and `/abs/notes` give the same document key and section ids, and re-ingesting under any spelling replaces the document's sections and clauses.
- A file shape no loader recognizes is drafted: the review queue records `loader_drafted` with a candidate loader `.rb` in `docs/ingest-review/candidates/` (a quarantine outside the autoloaded `lib/` tree) and a review doc in `docs/ingest-review/`. Nothing is registered automatically; promoting a draft is a manual review (see the recipe in the draft's review doc). A draft must pass three gates before it is written — class-name pattern, `RubyVM::AbstractSyntaxTree.parse` (parse, never `eval`) and a declared class under `SFL::Core::Loaders`. A gate failure records `draft_failed` and raises; the ingest loop catches it per file and the run continues (`lib/sfl/ingest/orchestrator.rb:96`); the syntax-parse and declared-class gates also leave a `<stem>-invalid.md` evidence doc naming the gate.
- Collection names are trimmed, keep their case and are unique ignoring case. An empty name is rejected.
- Tables: `collections`, `documents` (one row per `document_key`), `sections` (one row per `section_id`, nested through `parent_section_id`) and `runs`.
- Markdown sections nest by heading level (`lib/sfl/core/loaders/heading_tree.rb:17`); canvas sections are always top-level, with no parent (`lib/sfl/core/loaders/canvas_source.rb:63`). A heading is the parent of the sections that follow it until a heading of the same or a higher level. Turn sections have no parent, and their label is the speaker.
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
| `bundle exec exe/sfl-api` | HTTP API server (default port 3001; a flat routing table over the same Context collaborators the CLI uses — `lib/sfl/api/server.rb`) |
| `bundle exec exe/sfl-tui` | Terminal UI: browse, review, select and export; search |

Run `exe/sfl-analyze --help` for options.

## Terminal UI

`exe/sfl-tui` is built on `ratatui_ruby`. It has four tabs, switched with `1` to `4`: Browse, Search, Runs and Models. Runs lists the 50 newest runs in the `runs` table (ingest, annotate, export, recompile), newest first, re-read every 2 seconds; stalled and dead runs are marked. Models lists each task with its effective provider and model and the source: `env`, `db` or `default`. A task's model is the `SFL_TASK_<TASK>_MODEL` variable when set (the row is locked and names the variable), else its `task_models` row, else the default. `Enter` on a task lists the models that have the capability the task needs (embedding for `embedding`, chat for the rest); `Enter` on a model saves it to `task_models`; `Esc` goes back; `r` refreshes the `models` table. A task whose assigned model is unavailable is marked `! unavailable`. Each run row records the effective model per task in its `models` column. `q` or Ctrl-C quits. The bottom line lists the keys of the current tab.

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

`Enter` runs `exe/sfl-analyze ingest PATH --collection NAME [flags]` under a new `SFL_RUN_ID`; `Esc` closes the launcher. Inside kitty (`KITTY_WINDOW_ID` set and `KITTY_LISTEN_ON` reachable, which needs `allow_remote_control yes` and `listen_on` in `kitty.conf`) the ingest opens in a new kitty tab, where it draws its dashboard, and the tab stays open after it exits. Outside kitty, or when kitty refuses, the ingest runs as a detached child with its output in `SFL_INGEST_LOG_DIR/ingest-<run id>.log` (default `./output/logs`), and the TUI moves to the Runs tab, where the run appears.

The TUI is a pure update over immutable state — a deliberate design, kept simple on purpose: there is no desktop GUI, and review happens here, in the Browse tab.

## Setup

1. Start Postgres and Redis with `docker compose up -d` — Postgres carries the entire store; Redis (redis-stack, RedisInsight on 8001) is provisioned by the compose file and no application code consumes it yet.
2. Copy `.env.example` to `.env` and set the values you need.
3. Apply migrations with `bundle exec rake db:migrate`. `sfl-tui`, `sfl-analyze ingest` and `--store` runs exit with the current and latest schema versions when this step is missing.

`SFL::Boot` loads `.env`. With `SFL_AUTO_START_DOCKER=1` in the shell environment, the `exe/` scripts start the Docker services when they are not running.

For container-based development, a devcontainer definition — the `mcr.microsoft.com/devcontainers/ruby:2-3.4-trixie` image, RubyMine backend — lives at `docker/.devcontainer/devcontainer.json`. VS Code and JetBrains IDEs look for devcontainer configs under `.devcontainer/` at the repository root (VS Code also reads a root-level `.devcontainer.json`), so open this one explicitly, or move it there to make it discoverable.

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

Every line carries a run id because a run is the unit of accountability here: what happened, under which model, in which collection — findable in one query.

Examples:

```
SFL_LOG_TARGET=stderr,journald bundle exec exe/sfl-analyze conversation input.jsonl
journalctl SFL_RUN_ID=<id>
```

## Eval tasks

Eval runs on unseen conversations deliberately — a held-out set, so the score is evidence rather than rehearsal. Three tasks build and run it:

- `rake eval:build_narrative_dataset` loads the narrative digests into Langfuse.
- `rake eval:setup_langfuse` creates score configs and annotation queues.
- `rake eval:run_unseen` runs Pass 2 on unseen conversations and writes `output/eval/nd-<n>/`.

## Where the reasoning lives

The README carries the summary; the design record lives where it can be checked:

- `goals/` — feature goals, fact lists, and per-goal `decisions.md` rationale files.
- `features/` — the Gherkin acceptance scenarios and `features/qa-procedure.md`, the manual QA procedure that verifies them.
- `docs/ingest-review/` — the loader-draft review trail: each draft's provenance, gates and supersession record.
- `docs/gem-inventory.md` — the dependency audit.

## Directory layout

```
exe/             executables
lib/sfl/boot.rb  configuration and wiring (only code that accesses ENV)
lib/sfl/core/    types, ports, Pass 1, pipeline, loaders
lib/sfl/llm/     LLM engines, signatures, model configuration
lib/sfl/store/   Sequel repositories for Postgres and pgvector
lib/sfl/retrieval/  context synthesis
lib/sfl/analysis/   analysis engines and sources
lib/sfl/ingest/  ingest orchestration, deterministic rules, loader drafting
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
