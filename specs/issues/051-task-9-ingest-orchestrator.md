# Issue #51: Task 9: Ingest::Orchestrator

**Status:** OPEN
**Created:** 2026-08-07T02:38:26Z
**Updated:** 2026-08-07T02:46:03Z
**Author:** Robert Pannick (@b08x)
**URL:** https://github.com/b08x/sfl-engine/issues/51

## Description

Part of the [Intelligent Ingest Layer plan](docs/superpowers/plans/2026-08-06-intelligent-ingest-layer.md) (Task 9 of 10). Depends on Tasks 2, 4, 5, 8.

## Goal
Add `Ingest::Orchestrator`, coordinating classify → dispatch/review for one ingest run.

## Files
- Create: `lib/sfl/ingest/orchestrator.rb`
- Test: `spec/ingest/orchestrator_spec.rb`

## Interfaces
- Consumes: `Ingest::DeterministicRules.classify` (Task 5), `Core::Ports::Classifier#classify` (Task 4), `Ingest::LoaderDrafter#draft` (Task 8), `Store::PgIngestReviewRepository` (Task 2), `Analysis::Engine#analyze`, `Analysis::KnowledgeBaseSource#analyze`, `Analysis::ConversationSource.new`/`Analysis::DocumentationSource.new`.
- Produces: `Ingest::Orchestrator.new(conversation_engine:, kb_source:, classifier:, loader_drafter:, review_repo:, logger: Core::Ports::Null::Logger.new)`, `#run(path) -> Hash{dispatched:, review_entries:, drafted:}` (path may be a single file or a directory, walked recursively). Consumed by Task 10.

Includes F11 partial-failure isolation (one file's failure doesn't halt the run), a `CONFIDENCE_THRESHOLD = 0.6` gate, and `SAMPLE_BYTES = 4096` sampling for classifier/drafter calls.

## Checklist
- [ ] Write the failing spec
- [ ] Verify it fails
- [ ] Write the implementation
- [ ] Verify it passes
- [ ] Rubocop
- [ ] Commit

Full code is in the plan document, Task 9 section.

## Labels

None

## Assignees

None
