# Issue #53: Task 1: ingest_review_entries migration + test-db wiring

**Status:** OPEN
**Created:** 2026-08-07T02:38:33Z
**Updated:** 2026-08-07T02:38:33Z
**Author:** Robert Pannick (@b08x)
**URL:** https://github.com/b08x/sfl-engine/issues/53

## Description

Part of the [Intelligent Ingest Layer plan](docs/superpowers/plans/2026-08-06-intelligent-ingest-layer.md) (Task 1 of 10).

## Goal
Create the `ingest_review_entries` Postgres table and wire it into the test-db TRUNCATE list.

## Files
- Create: `db/migrations/009_create_ingest_review_entries.rb`
- Modify: `spec/support/store_test_db.rb:49-53` (add `ingest_review_entries` to the TRUNCATE list)

## Interfaces
Produces a `:ingest_review_entries` table with columns `id, path, status, format, mode, confidence, reasoning, loader_path, doc_path, created_at, resolved_at`, `status` defaulting to `"pending"`, indexed on `status`. Mirrors `review_queue`'s shape (`db/migrations/007_create_review_queue.rb`).

## Checklist
- [ ] Write the migration
- [ ] Add the table to `StoreTestDb.clean!`'s TRUNCATE list
- [ ] Run migrations against the test database (`bundle exec rake db:migrate`)
- [ ] Commit

Full code and exact diffs are in the plan document, Task 1 section.

## Labels

None

## Assignees

None
