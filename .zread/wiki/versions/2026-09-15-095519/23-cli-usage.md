The SFL Engine CLI is the primary scriptable interface for the two-pass annotation pipeline. It wraps `SFL::CLI` (`lib/sfl/cli.rb`), which owns argv parsing, terminal output, exit codes, and the four subcommands: `conversation`, `documentation`, `knowledge-base`, and `context`. Each subcommand is wired in `exe/sfl-analyze` through `SFL::CLI.run(ARGV)`; the binary sets up `$LOAD_PATH`, enables `$stdout.sync`, then calls `SFL::DockerServices.ensure_running!` before delegating to the CLI.

Sources: [exe/sfl-analyze](exe/sfl-analyze#L1-L18) | [lib/sfl/cli.rb](lib/sfl/cli.rb#L1-L677)

## Invocation

Run from the repository checkout because this is a non-gem application with no gemspec:

```bash
bundle exec exe/sfl-analyze <subcommand> <input> [options]
```

The `sfl-analyze` script itself (`exe/sfl-analyze`) performs three setup steps before any analysis runs:

1. Expands `../lib` onto `$LOAD_PATH` (the repo has no gemspec, so Bundler won't add `lib/` automatically) [exe/sfl-analyze#L4-L13].
2. Returns `$stdout.sync = true` so progress lines aren't trapped in the block buffer when stdout is redirected to a file or pipe [exe/sfl-analyze#L9-L11].
3. Calls `SFL::DockerServices.ensure_running!` and then `exit SFL::CLI.run(ARGV)` [exe/sfl-analyze#L15-L17].

Sources: [exe/sfl-analyze](exe/sfl-analyze#L1-L18)

## Subcommands

The CLI parses the first non-option argument as the command symbol (`conversation`, `documentation`, `knowledge_base`, `ingest`, `context`). Anything else raises `SFL::CLI::UsageError` and prints the usage text with exit code 1 [lib/sfl/cli.rb#L101-L110].

| Subcommand | Input | Purpose |
|---|---|---|
| `conversation` | `.jsonl`, `.srt`, `.vtt`, `.ass`, or a folder of any of these | Analyze a JSONL conversation, or a subtitle file treated as a single-conversation transcript [lib/sfl/cli.rb#L44-L49] |
| `documentation` | A `.md`/`.pdf` file or directory | Analyze one or more markdown/PDF documents [lib/sfl/cli.rb#L50-L51] |
| `knowledge-base` | A KB directory | Classify artifacts, score quality, and produce a migration manifest [lib/sfl/cli.rb#L51-L53] |
| `ingest` | A file or directory | Walk, classify each file, and dispatch it into the conversation/documentation/knowledge-base pipelines, or queue low-confidence/unrecognized files for review [lib/sfl/cli.rb#L54-L58] |
| `context` | `"<query>"` | Retrieve stored clauses and synthesize an answer [lib/sfl/cli.rb#L59-L60] |

Sources: [lib/sfl/cli.rb](lib/sfl/cli.rb#L40-L60) | [exe/sfl-analyze](exe/sfl-analyze#L1-L18)

### `conversation`

- **Input**: `.jsonl` (each line parsed with JSON.parse and filter-mapped to `{mes}`-shaped turns), `.srt`, `.vtt`, `.ass` subtitle files (parsed by `Core::Loaders::SubtitleSource`), and `.json` ChatGPT/Claude export files which are expanded by `Analysis::ChatExportExpander` into one native JSONL per conversation under `<output_dir>/_expanded`.
- **Directory inputs** produce one report per file, written into `<output-dir>/<file-label>/` subdirectories [lib/sfl/cli.rb#L44-L49].
- **Special behavior**: a `.srt/.vtt/.ass` file is inherently one conversation (no multi-conversation bundling); consecutive cues from the same speaker are merged into a single turn, so a subtitle file with no speaker info (plain SRT or ASS with uniform Name) yields one synthetic speaker and every cue merges into one continuous monologue [lib/sfl/core/loaders/subtitle_source.rb#L1-L20].
- **Failure isolation**: per-file exceptions are rescued and logged; the run continues with the remaining files [lib/sfl/cli.rb#L248-L266].

Sources: [lib/sfl/cli.rb](lib/sfl/cli.rb#L226-L266) | [lib/sfl/analysis/conversation_source.rb](lib/sfl/analysis/conversation_source.rb#L1-L112) | [lib/sfl/analysis/engine.rb](lib/sfl/analysis/engine.rb#L150-L190)

### `documentation`

- **Input**: a single `.md`/`.pdf` path or a directory.
- **Processing**: a single file is compiled through `Analysis::DocumentationSource` and `Engine#analyze` in one shot. `DocumentationSource` delegates to `MarkdownSource`/`PdfSource` per file and tracks `chunk_boundaries` so the `ChunkArtifactDetector` can flag PDF chunks split mid-sentence [lib/sfl/analysis/documentation_source.rb#L1-L20].
- **Output**: a `Core::Types::AnalysisResult` written to `--output-dir` plus an optional narrative report.

Sources: [lib/sfl/cli.rb](lib/sfl/cli.rb#L268-L284) | [lib/sfl/analysis/documentation_source.rb](lib/sfl/analysis/documentation_source.rb#L1-L133)

### `knowledge-base`

- **Input**: a KB directory containing `.md`, `.canvas`, `.pdf`, or image files (with `--images`).
- **Processing**: `Analysis::KnowledgeBaseSource` walks each file with the appropriate loader (`MarkdownSource`, `CanvasSource`, `PdfSource`, or `ImageSource` with a vision `chat:`) and compiles each artifact with `Pipeline#compile`. Every artifact receives a `content_type` (from `ContentTypeClassifier`), a `quality_score` (from `QualityScorer`), and a migration action (from `MigrationAssessor`). Failed artifacts are skipped without aborting the whole run [lib/sfl/analysis/knowledge_base_source.rb#L1-L50].
- **Output**: prints the generated report paths plus `Artifacts: N | Stale: N | Files: N` [lib/sfl/cli.rb#L286-L301].
- **Options**: `--store`, `--images`, `--no-images`, `--vision-model` (informational; mapped to image source injection in the KB source), `--resume`, `--annotated` (also write `annotated/*.md`).

Sources: [lib/sfl/cli.rb](lib/sfl/cli.rb#L286-L301) | [lib/sfl/analysis/knowledge_base_source.rb](lib/sfl/analysis/knowledge_base_source.rb#L1-L337)

### `ingest`

- **Input**: a file or directory.
- **Processing**: `Ingest::Orchestrator` is built from the existing `build_conversation_engine`/`build_kb_source` factories; it classifies each file, dispatches it to the conversation or knowledge-base pipelines, and queues low-confidence/unrecognized files for review via `Store::PgIngestReviewRepository` [lib/sfl/cli.rb#L393-L415].
- **Options**: only `--output-dir` and `--disable-tracing`; the `parse_ingest_options` surface is minimal by design [lib/sfl/cli.rb#L169-L180].

Sources: [lib/sfl/cli.rb](lib/sfl/cli.rb#L393-L415)

### `context`

- **Input**: a query string, e.g. `context "what happened?"` [lib/sfl/cli.rb#L59-L60].
- **Options**: `--output-dir DIR`, `--limit N` (default 10), `--mood MOOD` (declarative|interrogative|imperative|exclamative), `--min-tenor F`, `--max-tenor F`, `--min-modality F`, `--max-modality F`, and `--disable-tracing` [lib/sfl/cli.rb#L182-L195].
- The filters are forwarded as scalar stance filters to retrieval; the query synthesizes these stored clauses into an answer via `Retrieval::ContextSynthesizer`.

Sources: [lib/sfl/cli.rb](lib/sfl/cli.rb#L182-L195)

## Common Options

All subcommands accept these global flags, implemented by `add_tracing_option` so `--disable-tracing` behaves identically everywhere instead of being redefined per-subcommand [lib/sfl/cli.rb#L113-L118]:

| Option | Default | Effect |
|---|---|---|
| `--output-dir DIR` | `./output/latest` | Where reports are written [lib/sfl/cli.rb#L62-L63, L95] |
| `--disable-tracing` | `false` | Skip OpenTelemetry/Langfuse tracing setup [lib/sfl/cli.rb#L63] |

Sources: [lib/sfl/cli.rb](lib/sfl/cli.rb#L40-L95)

## Conversation / Documentation Options

These options are shared by `conversation` and `documentation` because `parse_documentation_options` delegates to `parse_conversation_options` [lib/sfl/cli.rb#L144-L146]:

| Option | Default | Effect |
|---|---|---|
| `--pass1-only` | `false` | Skip Pass 2 LLM annotation and stub every clause with placeholder values (mood: declarative, modality/tenor: 0.5, annotation_source: stub). Exempt from the fallback-exit-code rule because stubs are what the user asked for [lib/sfl/cli.rb#L66-L67] |
| `--narrative` | `false` | Also generate `narrative_report.md` via `Analysis::NarrativeGenerator` [lib/sfl/cli.rb#L67] |
| `--topics N` | `nil` | Fixed topic count for LDA; `0` = HDP (auto-discover) [lib/sfl/cli.rb#L68] |
| `--resume` | `false` | Reuse cached Pass 2 results from previous runs [lib/sfl/cli.rb#L69] |
| `--store` | `false` | Persist clauses + embeddings for the `context` command [lib/sfl/cli.rb#L70] |
| `--allow-fallback` | `false` | Exit 0 even when Pass 2 fell back to placeholder values for some clauses. OFF by default: a report whose tenor/modality scores are placeholders is a failed run, not a successful one; it must not be mistaken for success by a script reading the exit code [lib/sfl/cli.rb#L71-L77] |

Sources: [lib/sfl/cli.rb](lib/sfl/cli.rb#L61-L78) | [lib/sfl/analysis/engine.rb](lib/sfl/analysis/engine.rb#L40-L80)

### Knowledge-Base Options

| Option | Default | Effect |
|---|---|---|
| `--store` | `false` | Persist clauses + embeddings for `context` |
| `--images` / `--no-images` | `false` | Analyze image files via vision LLM (default off) [lib/sfl/cli.rb#L81] |
| `--vision-model MODEL` | `nil` | Vision LLM model id; currently informational only (LLM::ChatFactory#for lacks a per-call model-override parameter) [lib/sfl/cli.rb#L82-L84] |
| `--resume` | `false` | Reuse cached Pass 2 results [lib/sfl/cli.rb#L85] |
| `--annotated` | `false` | Also write `annotated/*.md` [lib/sfl/cli.rb#L86] |

Sources: [lib/sfl/cli.rb](lib/sfl/cli.rb#L79-L87)

## Context Options

| Option | Default | Effect |
|---|---|---|
| `--mood MOOD` | `nil` | declarative\|interrogative\|imperative\|exclamative [lib/sfl/cli.rb#L89] |
| `--min-tenor F` / `--max-tenor F` | `nil` | Scalar formality filter [lib/sfl/cli.rb#L90] |
| `--min-modality F` / `--max-modality F` | `nil` | Scalar certainty filter [lib/sfl/cli.rb#L91] |
| `--limit N` | `10` | Max clauses to retrieve [lib/sfl/cli.rb#L92] |
| `--output-dir DIR` | `nil` | Override the default output directory [lib/sfl/cli.rb#L85] |

Sources: [lib/sfl/cli.rb](lib/sfl/cli.rb#L88-L93)

## Exit Codes and Error Handling

`SFL::CLI.run(argv)` returns an integer exit code and never crashes for expected operational failures [lib/sfl/cli.rb#L196-L246]:

- **0**: successful run (or `--allow-fallback` with degraded annotations).
- **1**: usage error, `Boot::Error` (missing API key, DB connection failure, tracing cancellation), `Analysis::Error`, `Store::Error`, `Timeout::Error`, `LLM::Error`, or any accumulated per-file failures.
- **No exceptions leak**: the rescue chain maps each failure category to a message and exit code, ported verbatim from legacy's `CLI.run`. The only un-rescued case is `RuntimeError` (Ruby-level bugs), which still produces a backtrace [lib/sfl/cli.rb#L196-L246].

### Fallback Clause Handling

A clause whose `annotation_source` is **not** `llm` or `human` is a fallback/stub/chunk-artifact clause (see `Core::Types::TRUSTED_ANNOTATION_SOURCES = %w[llm human]`) [lib/sfl/core/types/trusted_annotation_sources.rb#L1-L16]. `finish_report` counts defaulted clauses and prints a percentage warning; `process_conversation_file` turns a positive count into a non-zero exit code (unless `--pass1-only` or `--allow-fallback`) [lib/sfl/cli.rb#L303-L321].

Sources: [lib/sfl/cli.rb](lib/sfl/cli.rb#L196-L321) | [lib/sfl/core/types/trusted_annotation_sources.rb](lib/sfl/core/types/trusted_annotation_sources.rb#L1-L16)

## Progress Reporting

Progress is displayed per turn (conversation) or per artifact (knowledge-base) with an ETA bar using `TTY::ProgressBar`. Interrupted runs (Ctrl+C) print a resume hint: `sfl-analyze <command> <input> --resume` skips cached turns and re-analyzes only the remainder [lib/sfl/cli.rb#L286-L301].

Sources: [lib/sfl/cli.rb](lib/sfl/cli.rb#L286-L301) | [lib/sfl/cli/turn_progress_bar.rb](lib/sfl/cli/turn_progress_bar.rb#L1-L37) | [lib/sfl/cli/artifact_progress_bar.rb](lib/sfl/cli/artifact_progress_bar.rb#L1-L24)

## Narrative Reports

With `--narrative`, the CLI generates `narrative_report.md` in the output directory. It uses the existing `Analysis::NarrativeGenerator::Digest.from_result` snapshot and a `LLM::Narrators::NarrativeGenerator` (chained via a narrator `proc`), then runs `Analysis::CitationGroundingChecker` to verify each claim is anchored to a source clause via `[clause-id]` markers [lib/sfl/cli.rb#L389-L432].

Sources: [lib/sfl/cli.rb](lib/sfl/cli.rb#L389-L432)

## Example Workflows

### Analyze a JSONL conversation

```bash
bundle exec exe/sfl-analyze conversation conversations.jsonl --store --narrative --topics 0
```

- `--store` persists clauses and embeddings so `context` can query them later.
- `--narrative` additionally writes `narrative_report.md`.
- `--topics 0` uses HDP topic modeling (auto-discovered).

### Analyze a documentation directory

```bash
bundle exec exe/sfl-analyze documentation ./docs/ --store --output-dir ./analysis/latest
```

### Assess a knowledge base for migration

```bash
bundle exec exe/sfl-analyze knowledge-base ./my-kb --store --images --annotated
```

Prints `Artifacts: N | Stale: N | Files: N` and, with `--annotated`, writes annotated markdown files.

### Query stored clauses

```bash
bundle exec exe/sfl-analyze context "what happened?" --limit 10 --mood declarative --store
```

### Ingest a directory of mixed files

```bash
bundle exec exe/sfl-analyze ingest ./raw-media/ --output-dir ./output/latest
```

Sources: [lib/sfl/cli.rb](lib/sfl/cli.rb#L40-L93) | [README.md](README.md#L120-L140)

## Architecture Notes

- **Delegation, not duplication**: `SFL::CLI` has four `run_*` use-case drivers and one pipeline factory. `build_conversation_engine` and `build_kb_source` share the same `build_pipeline`/`build_collaborators` helpers, and `build_ingest_orchestrator` reuses both engines for the `ingest` subcommand [lib/sfl/cli.rb#L434-L455].
- **Pass 1 runs as a subprocess**: `SFL::Boot#resolve_pass1_command` builds the spaCy sidecar command `[interpreter, spacy_sidecar_script, --model <spacy_model>]`, and `Pipeline` only shells it out via Open3.popen2. No PyCall or GIL/GVL issues [lib/sfl/boot.rb#L239-L261].
- **No auto-migration**: `SFL::Boot#connect_db` only connects and installs Postgres extensions; `rake db:migrate` is an explicit separate step [lib/sfl/store/database.rb#L1-L75, Rakefile].
- **Exit-code semantics**: `--allow-fallback` exists because a run whose interpersonal values are placeholders is still useful for debugging Pass 1, but a caller reading the exit code must never be told the run succeeded.

Sources: [lib/sfl/cli.rb](lib/sfl/cli.rb#L1-L677) | [lib/sfl/boot.rb](lib/sfl/boot.rb#L1-L261) | [lib/sfl/core/pipeline.rb](lib/sfl/core/pipeline.rb#L1-L265) | [Rakefile](Rakefile#L1-L80)

## Related Pages

- [Core Pipeline Architecture](7-two-pass-pipeline-architecture) — Pass 1 Pass 2, Pipeline, and Pipeline#compile options.
- [Database Schema](18-database-schema) — Postgres tables, `PgClauseStore`, and `PgEmbeddingStore`.
- [HTTP API Reference](24-http-api-reference) — `/pipeline/compile`, `/retrieve`, `/synthesize` for HTTP access to the same engine.
- [Roda Routes Architecture](25-roda-routes-architecture) — The Flask HTTP surface that shares `SFL::API::Context` with the CLI.