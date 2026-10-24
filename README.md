# SFL Engine

SFL Engine annotates text with Systemic Functional Linguistics (SFL) metadata and uses that metadata when retrieving text for an LLM. The mechanism fits in one sentence; the convictions behind it take a page, and the page comes first because it explains most of the unusual decisions the operational sections below build on.

## Why this engine exists

Most retrieval systems can answer *what is this text about?*. Very few can answer *how was it said?* — and by "how," I mean stance: whether a sentence asserts, hedges, instructs or worries; whether a speaker positions themselves above, below or alongside the listener; whether a claim is presented as a finding or offered as a guess. Vector similarity tends to average those distinctions away, and I find that a real loss, because stance is exactly the dimension a careful reader notices first.

The theory that names those distinctions is Systemic Functional Linguistics — Halliday's account of language as choice-in-context, in which one clause simultaneously does several kinds of work, its *metafunctions*: an **ideational** payload (what happened: processes, participants, circumstances) and an **interpersonal** payload (how it is presented: mood, modality, tenor, attitude). Halliday's theory also describes a third, *textual* metafunction; the engine's payload split keeps the two that retrieval filters on and stores no textual payload. ("Metafunction" is a technical term, not a metaphor — it names the different kinds of meaning one clause carries at once.)

SFL has mostly been a close-reading framework for humans. This engine uses it the other way round: as a feature-extraction schema for machines. Annotation turns stance from something a prompt can *ask* a model to respect into something a query can *filter on* — and that difference is structural. A prompt instruction is a suggestion; a scalar filter that excludes a clause before the model's context is ever assembled is a guarantee. The engine's founding bet is that the second kind of defense is the one worth engineering.

Two storage decisions follow from that bet:

- **Payload separation.** The ideational and interpersonal payloads do not share a table. Facts live in one place, tone in another. This is not normalization for its own sake; it is what makes "how was this said" a filterable dimension in its own right rather than a paraphrase of "what was said." Retrieval can filter clauses by their interpersonal values before any text reaches the LLM.
- **Clause-level units.** The unit of storage and retrieval is the clause, not a token-count chunk. A fixed-size chunk is a computational convenience; a clause is a complete unit of meaning — one process, its participants, its circumstances, one stance — so what gets retrieved is whole.

## Design principles

Each principle below is enforced somewhere checkable — a spec, a gate or a code path — noted inline.

1. **Defense is structural, not behavioral.** Retrieval filters run against stored metadata, before the model's context is assembled. A clause that fails the filter never enters the context window (spec/store/pg_hybrid_retriever_spec.rb).
2. **LLM output is untrusted data, never code.** When ingest meets a file shape no loader recognizes, the LLM's candidate loader is parsed (never `eval`'d), gated on three checks, and written into a quarantine directory the runtime never loads. Promotion into `lib/` is a human copy, never a code path. Incident `4a53727` — one bad draft dropped into the autoloaded tree, failing the whole test suite — is why this is a permanent constraint rather than a preference.
3. **One bad input never halts the run.** Ingest isolates failure per file: a file that fails is recorded in the review queue, and the rest of the run continues.
4. **Degradation is truthful, never silently fudged.** An out-of-range annotation value is rejected by contract and degraded with recorded provenance, not rescaled to fit. Fallback annotations are marked as fallback and excluded by default from what the synthesis LLM sees and cites — `include_fallback: true` (exposed by the HTTP API) opts back in, and the result reports the exclusion, so a fallback never silently grounds an answer (spec/llm/degradation_spec.rb).
5. **Determinism where rules work; models where semantics need them.** Pass 1 is deterministic syntactic parsing; Pass 2 is LLM annotation. Annotation provenance is recorded — a fallback value is marked as fallback — so a degraded value is never mistaken for a finding (spec/llm/degradation_spec.rb).
6. **Citations are checked, not trusted.** The context synthesizer maps the model's citation numbers to real clause ids and drops the out-of-range ones.
7. **Configuration flows one way.** `SFL::Boot` is the only code that reads `ENV`; every other class receives its configuration as injected arguments, and a spec fails on any other `ENV` read under `lib/`, `exe/` or `rakelib/`.
8. **Review is human and named.** Review decisions are refused without `SFL_REVIEWER_NAME`, and annotation review is read-only in the UI — the decision trail is not editable from the review screen.
9. **Naming is vocabulary.** *Document*, *section* and *clause* mean specific things (see the Glossary), everywhere — code, specs, CLI output and docs.
10. **Docs are audit, not brochure.** `docs/gem-inventory.md` records what every dependency does — and which ones do nothing — with cited call sites; documentation commits pin claims to verified behavior.

## How the engine works

The engine compiles text into annotated clauses in two passes with a hard boundary between them:

- **Pass 1** — deterministic syntactic parsing that finds clauses, process types, participants and circumstances. It runs as a Python spaCy sidecar over NDJSON, behind a typed port, so the rest of the codebase never sees the transport and tests can swap in fakes. The pipeline composes the passes through a Result ladder: a Pass 1 failure short-circuits straight past everything downstream.
- **Pass 2** — LLM annotation of mood, modality, tenor and attitude, producing the interpersonal payload. The model is set per task through `SFL_TASK_*` variables. Batches are bounded (40 clauses per Pass 2 request), and provider-side failures back off and retry instead of filling the run with placeholders.
- **Store** — Postgres with pgvector holds the clauses, their separated payloads, embeddings and review queues. One database, one place to filter and search within a transaction.
- **Retrieval** — hybrid retrieval (reciprocal-rank fusion over vector and lexical search, plus scalar filters over the stored metadata), followed by context synthesis that only cites clauses that exist.
- **Analysis** — engines and scorers that run over conversations, documentation and knowledge bases.
- **Eval** — Langfuse datasets and a runner that evaluates on *unseen* conversations, held out on purpose.

Everything below this line is operational reference.

## Glossary

- Collection: a named group of documents.
- Document: one whole item, such as a paper, a transcript or one chat conversation.
- Section: a segment of a document, such as a heading block or one speaker turn. Identified by `section_id`, for example `notes-3f9a1c2e#turn-3`. A file loader's prefix before `#` is the basename plus the first 8 hex digits of the SHA-256 of the file path (`Core::Loaders::FileId`), so two files with the same basename get different section ids and re-ingesting a file keeps its ids.
- Clause: what annotation produces from a section. Each clause row carries the `section_id` of its section. Retrieval filters on `mood` (a closed set), `tenor` and `modality` (each 0.0-1.0), `process_type` (ideational payload) and `source_type`; the free-text `speaker_attitude` is stored but not filterable. Each row also stores `annotation_source` — `llm`, `human`, `fallback`, `stub` or `chunk_artifact` — provenance that drives the default citation exclusion, not a scalar filter.

## Collections, documents, sections and runs

- `sfl-analyze ingest <path> --collection NAME` stores clauses and records each document and section in collection NAME. The collection is created when it does not exist. Without `--collection`, the name is the basename of `<path>`. `conversation --store` and `documentation --store` take the same option.
- A file shape no loader recognizes is drafted: the review queue records `loader_drafted` with a candidate loader `.rb` in `docs/ingest-review/candidates/` (a quarantine outside the autoloaded `lib/` tree) and a review doc in `docs/ingest-review/`. Nothing is registered automatically; promoting a draft is a manual review (see the recipe in the draft's review doc). A draft must pass three gates before it is written — class-name pattern, `RubyVM::AbstractSyntaxTree.parse` (parse, never `eval`) and a declared class under `SFL::Core::Loaders`. A gate failure records `draft_failed` and raises; the syntax-parse and declared-class gates also leave a `<stem>-invalid.md` evidence doc naming the gate.
- Collection names are trimmed, keep their case and are unique ignoring case. An empty name is rejected.
- Tables: `collections`, `documents` (one row per `document_key`), `sections` (one row per `section_id`, nested through `parent_section_id`) and `runs`.
- Markdown and canvas sections nest by heading level. A heading is the parent of the sections that follow it until a heading of the same or a higher level. Turn sections have no parent, and their label is the speaker.
- A JSON records file — a Claude `conversations.json` or a ChatGPT conversations export — is streamed by `JsonRecordsSource` (catalog key `:claude_export`): one document per conversation record, keyed by the record's `uuid`, with the export file as its source path; each yielded message is one section, `section_id` `<uuid>#turn-N` with N counting from 0. A SillyTavern session file is one document keyed by its file path; each physical line is one complete JSON record and yields one section.
- `sfl-analyze json-records <file> [...] --collection NAME` ingests JSON records files one file at a time; without `--collection` the name is the basename of the first file's directory. Each file's units are written inside one transaction, so a failed file leaves nothing behind. The run summary lists each failed, redundant and skipped record with its byte offset, record index and reason, then `processed N, skipped ..., failed N, stale_removed N`; the exit status is 1 when any file failed. A failed file whose conversation uuids all appear intact in another file of the same batch is reported redundant, not failed. At the end of the run, sections of a re-ingested document that this run did not write are removed.
- Ingesting a document whose key exists in another collection moves it, with its sections, and logs a `document moved` warning naming both collections. Re-ingesting into the same collection replaces its sections and clauses.
- A section id that is already stored under another document is refused with `SectionRegistry::ConflictError`. In a knowledge-base ingest, `KnowledgeBaseSource` skips only the conflicting unit, prints a warning, and stores the file's other units. In a conversation or documentation ingest, the error stops that file and ingest records it as a `draft_failed` review entry; units stored before the conflict stay stored. `ingest` expands `<path>` to an absolute path, so `notes`, `./notes` and `/abs/notes` give the same document key and section ids, and re-ingesting under any spelling replaces the document's sections and clauses.
- Migration 016 puts clauses stored before collections existed into a collection named `legacy`: one document per section id prefix before `#`, one section per section id.
- `bundle exec rake db:purge_collection[NAME]` deletes a collection with its documents, sections and clauses and prints the counts.
- `bundle exec rake db:archive_document[KEY]` sets `archived_at` on a document, by exact `document_key`; `db:unarchive_document[KEY]` clears it. Hybrid retrieval (`PgHybridRetriever`) excludes archived documents; `db:prune_missing_sources[dry-run]` deletes documents whose source file is gone, with their sections and clauses, unless they are archived — pass `dry-run` to change nothing and print the counts only. Archiving changes two behaviors — hybrid retrieval stops returning the document's clauses, and `db:prune_missing_sources` spares it; the document itself stays visible in the TUI's Browse tab.
- `bundle exec rake models:refresh` fills the `models` table from the `ruby_llm` registry and the Ollama and OpenRouter listings. A model missing from its provider's latest listing is marked unavailable; its row is kept. A provider whose listing fails is left unchanged, and the task exits non-zero.
- Stored runs (`ingest`, and `conversation`/`documentation` with `--store`) write one `runs` row keyed by `SFL_RUN_ID`, with kind, collection, status, total, done, failed, current item, pid, the effective model per task (the `models` column) and start, heartbeat and finish times. The heartbeat is written every 5 seconds. A running row whose heartbeat is older than 30 seconds is shown as stalled; one whose process no longer exists is shown as dead.

## Entry points

| Command | Purpose |
|---|---|
| `bundle exec exe/sfl-analyze` | CLI: `conversation`, `documentation`, `knowledge-base`, `ingest`, `json-records` and `context` subcommands |
| `bundle exec exe/sfl-api` | HTTP API server (default port 3001) |
| `bundle exec exe/sfl-tui` | Terminal UI: browse, review, select and export; search |

Run `exe/sfl-analyze --help` for options.

On a terminal, a foreground ingest or annotation run shows a full-screen dashboard: run id, collection, models per task, elapsed time, ingest and annotation progress, the log, and Ctrl-C for a graceful stop; a second Ctrl-C aborts immediately. The final screen stays until a key is pressed.

## Terminal UI

`exe/sfl-tui` is built on `ratatui_ruby`. It has four tabs, switched with `1` to `4`: Browse, Search, Runs and Models. Runs lists the newest 50 runs in the `runs` table (ingest, annotate, export, recompile), re-read every 2 seconds; stalled and dead runs are marked. Models lists each task with its effective provider and model and the source: `env`, `db` or `default`. A task's model is the `SFL_TASK_<TASK>_MODEL` variable when set (the row is locked and names the variable), else its `task_models` row, else the built-in default: the free OpenRouter model (`google/gemma-4-26b-a4b-it:free`) for most chat tasks, Ollama's `embeddinggemma-2:440m` for the embedding task, and another task's effective model for context synthesis, narrative generation, loader drafting and ingest classification — so a task with nothing assigned makes no paid call. `Enter` on a task lists the models that have the capability the task needs (embedding for `embedding`, chat for the rest); `Enter` on a model saves it to `task_models`; `Esc` goes back; `r` refreshes the `models` table. A task whose assigned model is unavailable is marked `! unavailable`. Each run row records the effective model per task in its `models` column. `q` or Ctrl-C quits. The bottom line lists the keys of the current tab.

Browse shows collections, documents and nested sections on the left, the focused section's clauses in the middle and detail on the right.

- `↑`/`↓` move, `Tab` switches between the tree and the clause list, `Enter` expands or collapses a row.
- `f` cycles the status filter: all, pending review, accepted, rejected.
- A section with a pending content-review item shows `[R]`. Its detail shows the generated text, the reason and the source file. `A` approves, `R` rejects, `E` opens the text in `$VISUAL` or `$EDITOR`, recompiles the section (recorded as a `recompile` run) and records an edit. `o` shows an image item's source file. Inside kitty it is shown with `kitten icat` in an overlay window; press a key to return. Outside kitty it opens with `xdg-open`. Decisions are recorded under `SFL_REVIEWER_NAME`; without it they are refused.
- A clause with a pending annotation review shows `[A]`, and its detail shows the confidence. Annotation review is read-only here.
- `Space` selects the focused row and its descendants; a parent with only some descendants selected shows `[~]`. `a` selects every row at the current level, `Esc` clears. The status line shows the selected section and clause counts.
- `e` asks for a format (`j` JSONL, `m` Markdown) and writes the selected clauses, once each, in document and section order, to `<collection>-<timestamp>.jsonl|md` under `SFL_EXPORT_DIR` (default `./output/exports`). The export is recorded as an `export` run and its path is shown in the status line.

Search (`/` to type, `Enter` to run) uses the hybrid retriever (`PgHybridRetriever`) and shows each hit's collection, document and section.

`i` opens the ingest launcher over any tab. It has three fields; `Tab` and `Shift-Tab` move between them:

- Path: the file or folder to ingest.
- Collection: an existing collection, chosen with `↑`/`↓`, or a new name. When it is empty, the collection is the path's base name.
- Flags: other `ingest` flags, `--output-dir DIR` and `--disable-tracing`. Unknown flags are refused.

`Enter` runs `exe/sfl-analyze ingest PATH --collection NAME [flags]` under a new `SFL_RUN_ID`; `Esc` closes the launcher. Inside kitty (`KITTY_WINDOW_ID` set and `KITTY_LISTEN_ON` reachable, which needs `allow_remote_control yes` and `listen_on` in `kitty.conf`) the ingest opens in a new kitty tab, where it draws its dashboard, and the tab stays open after it exits. Outside kitty, or when kitty refuses, the ingest runs as a detached child with its output in `SFL_INGEST_LOG_DIR/ingest-<run id>.log` (default `./output/logs`), and the TUI moves to the Runs tab, where the run appears.

The TUI is a pure update over immutable state; there is no desktop GUI — review happens here, in the Browse tab.

## Setup

1. Install the Ruby version pinned in `.ruby-version`, then `bundle install`.
2. Start Postgres and Redis with `docker compose up -d`.
3. Copy `.env.example` to `.env` and set the values you need. The store's vector column is fixed at 768 dimensions, so any model assigned to the embedding task (`SFL_TASK_EMBEDDING_MODEL`) must emit 768-dim vectors.
4. Apply migrations with `bundle exec rake db:migrate`. `sfl-tui`, `sfl-analyze ingest` and `--store` runs exit with the current and latest schema versions when this step is missing.

`SFL::Boot` loads `.env`. With `SFL_AUTO_START_DOCKER=1` in the shell environment, `exe/sfl-analyze` and `exe/sfl-tui` start the Docker services when they are not running; `exe/sfl-api` does not, so it needs the services up first.

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
- When stdout or stderr is not a terminal — so no dashboard is drawn — the CLI writes `progress turn=N total=M` to stderr after each finished turn, regardless of `SFL_LOG_TARGET`.

Every line carries a run id because a run is the unit of accountability here: what happened, under which model, in which collection — findable in one query.

Examples:

```
SFL_LOG_TARGET=stderr,journald bundle exec exe/sfl-analyze conversation input.jsonl
journalctl SFL_RUN_ID=<id>
```

## Eval tasks

- `rake eval:build_narrative_dataset` loads the narrative digests — from `output/`, a sibling `sfl-compiler` checkout's `output/` and `output/eval/` — into Langfuse.
- `rake eval:setup_langfuse` creates score configs and annotation queues.
- `rake eval:run_unseen` runs Pass 2 on unseen conversations and writes `output/eval/nd-<n>/`.

## Where the reasoning lives

The README carries the summary; the design record lives where it can be checked:

- `goals/` — feature goals, fact lists, and per-goal `decisions.md` rationale files (local working notes, not committed).
- `features/` — the Gherkin acceptance scenarios and `features/qa-procedure.md`, the manual QA procedure that verifies them.
- `docs/ingest-review/` — the loader-draft review trail: each draft's provenance, gates and supersession record.
- `docs/gem-inventory.md` — the dependency audit.

## Directory layout

```
exe/             executables
sidecar/         Python spaCy Pass 1 sidecar
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
lib/sfl/dashboard/  full-screen run dashboard
lib/sfl/tui/     terminal UI (ratatui_ruby)
lib/sfl/export/  JSONL and Markdown export of selected clauses
features/        Gherkin acceptance scenarios and QA procedure
docs/            ingest-review trail and dependency audit
rakelib/         rake tasks
spec/            RSpec specs
db/              database migrations
docker/          Dockerfile and database init script
```
