# Issue #52: Task 10: sfl-analyze ingest CLI subcommand

**Status:** OPEN
**Created:** 2026-08-07T02:38:26Z
**Updated:** 2026-08-07T02:46:03Z
**Author:** Robert Pannick (@b08x)
**URL:** https://github.com/b08x/sfl-engine/issues/52

## Description

Part of the [Intelligent Ingest Layer plan](docs/superpowers/plans/2026-08-06-intelligent-ingest-layer.md) (Task 10 of 10). Depends on Tasks 7, 9.

## Goal
Add the `sfl-analyze ingest` CLI subcommand.

## Files
- Modify: `lib/sfl/cli.rb:37-99` (`USAGE`, `parse`), add `parse_ingest_options`, add `run_ingest`, add `build_ingest_orchestrator`
- Test: `spec/cli/parse_spec.rb` (add ingest parsing examples), create `spec/cli/run_ingest_spec.rb`

## Interfaces
- Consumes: `Ingest::Orchestrator` (Task 9), `Boot.call` (with `require_llm: true`), `Store::PgIngestReviewRepository` (Task 2), `SFL::CLI.build_conversation_engine`/`build_kb_source` (existing, reused unchanged).
- Produces: `sfl-analyze ingest <path> [--output-dir DIR] [--dry-run] [--disable-tracing]`. `--dry-run` classifies every file and prints what *would* happen without dispatching or writing to the DB — a separate, simpler code path rather than a flag threaded through `Orchestrator`.

## Checklist
- [ ] Read `lib/sfl/cli.rb` in full
- [ ] Write the failing spec additions
- [ ] Verify they fail
- [ ] Add the `ingest` subcommand to `USAGE` and `parse`
- [ ] Write `parse_ingest_options`
- [ ] Write `run_ingest` and `build_ingest_orchestrator`
- [ ] Verify specs pass
- [ ] Run the full suite (first cross-task regression check)
- [ ] Rubocop
- [ ] Manual smoke test (`bundle exec exe/sfl-analyze ingest ./spec/fixtures --dry-run`)
- [ ] Commit

Full code is in the plan document, Task 10 section.

## Labels

None

## Assignees

None
