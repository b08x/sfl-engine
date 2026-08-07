# Issue #44: Task 2: Store::PgIngestReviewRepository

**Status:** OPEN
**Created:** 2026-08-07T02:38:19Z
**Updated:** 2026-08-07T02:43:29Z
**Author:** Robert Pannick (@b08x)
**URL:** https://github.com/b08x/sfl-engine/issues/44

## Description

Part of the [Intelligent Ingest Layer plan](docs/superpowers/plans/2026-08-06-intelligent-ingest-layer.md) (Task 2 of 10). Depends on Task 1.

## Goal
Add `Store::PgIngestReviewRepository`, a Postgres-backed repository for the `ingest_review_entries` table.

## Files
- Create: `lib/sfl/store/pg_ingest_review_repository.rb`
- Test: `spec/store/pg_ingest_review_repository_spec.rb`

## Interfaces
- Consumes: `Sequel::Database` (`db:`), the `ingest_review_entries` table from Task 1.
- Produces: `Store::PgIngestReviewRepository.new(db)` with:
  - `#enqueue(path:, status:, reasoning:, format: nil, mode: nil, confidence: nil, loader_path: nil, doc_path: nil) -> String` (new row's id)
  - `#find(id) -> Hash | nil`
  - `#resolved?(path) -> Boolean` (used by `Ingest::Orchestrator` in Task 9 to skip already-resolved paths on rerun)

## Checklist
- [ ] Write the failing spec
- [ ] Verify it fails
- [ ] Write the implementation
- [ ] Verify it passes
- [ ] Rubocop
- [ ] Commit

Full code is in the plan document, Task 2 section.

## Labels

None

## Assignees

None
