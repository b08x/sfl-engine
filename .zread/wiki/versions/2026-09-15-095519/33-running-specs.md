` tags.

<blog>
# Running Specs

This page covers how the suite is configured, how the `sfl-analyze` command is executed, and what the tests actually assert. The entry point is the `SFL::CLI` module found at `lib/sfl/cli.rb`; the executable is `exe/sfl-analyze`; the RSpec harness is `spec/spec_helper.rb` with `--require spec_helper` and `--format documentation` set in `.rspec`.

## The entry point: `sfl-analyze` and `SFL::CLI.run`

Every spec run should be launched the same way the CLI is launched. `exe/sfl-analyze` requires the repo's `lib/` on the load path, forces `$stdout.sync` so progress lines are not stuck in block buffers when stdout is redirected, ensures Docker services are healthy via `SFL::DockerServices.ensure_running!`, then delegates to `SFL::CLI.run(ARGV)` and uses that return value as the process exit code.

`SFL::CLI.run` parses argv into a `{command:, input:, options:}` hash, dispatches to the matching `run_*` method, and applies a final fallback: if a `run_*` method returns an `Integer`, that integer is the exit code; otherwise the run exits `0`. All expected operational failures are rescued and translated into a clean `[ERROR]` message plus exit code `1` — never an unhandled backtrace.

- `UsageError` (unknown subcommand, missing input): prints usage to stderr and returns `1`.
- `Boot::Error`, `Analysis::Error`, `Store::Error`, `Timeout::Error`: prints `[ERROR] #{e.message}` and returns `1`.
- `LLM::Error`: prints `[ERROR] LLM provider error: #{e.message}` and returns `1`.

Sources: [exe/sfl-analyze](exe/sfl-analyze), [lib/sfl/cli.rb#L1-L87](lib/sfl/cli.rb#1-87), [lib/sfl/cli.rb#L175-L196](lib/sfl/cli.rb#L175-L196)

## Spec configuration and coverage

`spec/spec_helper.rb` boots `SimpleCov` with branch coverage enabled and configures the suite: chain-clause descriptions, partial-double verification, shared-context metadata behavior, focus-run support, an `spec/examples.txt` example-status persistence file, explicit random ordering with `Kernel.srand`, and the `doc` formatter whenever only one spec file is executed.

`.rspec` fixes the global options: `--require spec_helper`, `--format documentation`, and `--color`.

Sources: [spec/spec_helper.rb](spec/spec_helper.rb), [.rspec](.rspec)

## What the CLI specs assert

`spec/cli/run_spec.rb` verifies the exit-code contract end to end. The core case: `SFL::CLI.run(["context", "does it work?"])` returns `0` and dispatches `run_context` with the input and `limit: 10`. The error cases each stub the target `run_*` method to raise its specific error class and assert that the exact `[ERROR]` message appears on stderr and that the status is `1`.

The most important behavior in this file is the handling of **placeholder degradation**. Before these specs were written, a conversation that annotated 0 of 134 clauses could exit `0` with a green suite. The contract now asserts: a conversation whose Pass 2 annotations fell back to placeholder values still writes its artifacts (a degraded report is useful for debugging Pass 1), while the process exit code is non-zero, so nothing reading the exit code mistakes placeholders for findings.

Sources: [spec/cli/run_spec.rb](spec/cli/run_spec.rb)

## The run pipeline: from CLI to artifacts

Each `run_*` method follows the same shape. The CLI wires collaborators through a small set of factories, boots the pipeline, compiles every unit, writes the report trio, and returns an exit code based on how many units were degraded or failed.

For a conversation run, the loop is:

1. Build a `StopFlag` and install an interrupt trap.
2. `Boot.call(require_llm: !options[:pass1_only], require_tracing: !options[:disable_tracing])`.
3. `build_conversation_engine` creates a `Core::Pipeline` through `build_pipeline`, an `Analysis::Engine`, and a `TurnProgressBar`.
4. `gather_conversation_files` walks the input: native `.jsonl/.srt/.vtt/.ass` pass through as-is, `.json` ChatGPT/Claude exports are expanded by `Analysis::ChatExportExpander` into per-conversation JSONL files under `<output_dir>/_expanded`, and dynamic formats (`.md/.txt/.rtf/.csv/.tsv/.log`) expand using an LLM when tracing is enabled.
5. Each file is processed in isolation: `engine.analyze` compiles it, `finish_report` writes the CSV/JSON/Markdown trio and counts fallback clauses, and the per-file result feeds `exit_status_for`.

The loop is generous by design — a single file's failure (embedding-model mismatch, malformed export, provider timeout) is rescued per file, so one bad conversation in a batch does not abort the rest. The exit status is `0` only when the failure list is empty.

Sources: [lib/sfl/cli.rb#L175-L262](lib/sfl/cli.rb#L175-L262), [lib/sfl/cli.rb#L300-L306](lib/sfl/cli.rb#L300-L306), [lib/sfl/cli.rb#L308-L343](lib/sfl/cli.rb#L308-L343)

## Exit-code logic is based on degradation, not on success

`finish_report` writes the artifacts, then counts every clause whose `interpersonal.annotation_source` is not in `Core::Types::TRUSTED_ANNOTATION_SOURCES`. If that count is positive, it warns with a percentage and returns the count. `process_conversation_file` turns a positive count into a non-zero exit code, so this number is the run's verdict, not a cosmetic warning.

`Analysis::Engine#analyze` decides whether a run is "interrupted": if `turns.size < total` after the compile loop, `interrupted` is `true` in the result metadata. The TUI uses `--resume` to skip cached turns and only re-analyze the rest.

`--resume` wires a `Core::Ports::FileCache` into the pipeline. Inside `Core::Pipeline#compile`, `annotate` checks `resume && document_id`: when both are truthy, the pipeline first tries `annotate_with_cache` and serves Pass 2 results from the cache. `--pass1-only` is deliberately asymmetric: it short-circuits `annotate` with `stub_annotate_all`, which feeds every clause mood `declarative`, modality/tenor `0.5`, and `annotation_source: stub`. A fully-stubbed run is therefore a valid pass-1-only outcome, and `--allow-fallback` is the explicit opt-out for batch runs that accept partial degradation.

Sources: [lib/sfl/core/pipeline.rb#L60-L135](lib/sfl/core/pipeline.rb#L60-L135), [lib/sfl/cli.rb#L446-L476](lib/sfl/cli.rb#L446-L476), [spec/cli/run_conversation_spec.rb](spec/cli/run_conversation_spec.rb)

## Which specs exist

The suite is organized by concern. The CLI specs live under `spec/cli/`; the store specs under `spec/store/`; and the analysis/LLM specs under `spec/llm/` and `spec/analysis/`. Notably, `spec/retrieval/` is empty — retrieval is covered by the `store` specs (`spec/store/pg_hybrid_retriever_spec.rb`, etc.) rather than by a dedicated retrieval spec directory.

Sources: [spec/cli](spec/cli), [spec/store](spec/store), [spec/analysis](spec/analysis), [spec/llm](spec/llm), [spec/retrieval](spec/retrieval)

## Rough command reference

| Goal | Command |
|---|---|
| Run the full suite | `bundle exec rspec` (default task in `Rakefile`; also runs `rubocop` and `zeitwerk:check`) |
| Run specs with documentation formatting | `bundle exec rspec --format documentation` (the `.rspec` default) |
| Run one spec file | `bundle exec rspec spec/cli/run_spec.rb` |
| Run specs for a single directory | `bundle exec rspec spec/cli/ spec/store/` |
| Re-drive stale embeddings (F11) | `rake embeddings:redrive` |
| Run pending migrations against a test database | `rake db:migrate` (points at the `sfl_engine_v2_test` database via `spec/support/store_test_db.rb`) |
| Start the test database | `docker-compose up postgres` (auto-creates `sfl_engine_v2_test` from `docker/init-test-db.sql`) |

Sources: [Rakefile](Rakefile), [spec/support/store_test_db.rb](spec/support/store_test_db.rb)

## How to read a failing spec

1. Look at the `describe` and `it` blocks — the file under test and the specific contract. `spec/cli/run_spec.rb` tests the exit-code contract; `spec/cli/run_conversation_spec.rb` tests the degraded-run contract.
2. Check the stub: `allow(...).to receive(...)` mocks the real implementation of the collaborator so the test is fast and deterministic.
3. Inspect the expected output via `output(...)` matchers, e.g. `output(%r{1/2 clauses \(50.0%\) carry fallback}).to_stderr` — this pins both the message and the exit status.
4. If a spec requires a database, confirm the test database exists (`postgresql://sfl:sfl@localhost:5433/sfl_engine_v2_test`), that `db/migrations` are current, and that `StoreTestDb.clean!` is being called.

Sources: [spec/cli/run_conversation_spec.rb](spec/cli/run_conversation_spec.rb), [spec/support/store_test_db.rb](spec/support/store_test_db.rb)

## What still has no spec

The `spec/retrieval/` directory exists but contains no spec files. Retrieval behavior is instead covered through Postgres-backed repository specs: `spec/store/pg_hybrid_retriever_spec.rb`, `spec/store/pg_clause_store_spec.rb`, `spec/store/pg_embedding_store_spec.rb`, `spec/store/pg_review_queue_repository_spec.rb`, and `spec/store/pg_annotation_review_repository_spec.rb`. If you add a new retrieval feature, the first place to look is those repository specs rather than a new directory under `spec/retrieval`.