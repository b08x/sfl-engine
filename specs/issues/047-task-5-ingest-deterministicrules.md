# Issue #47: Task 5: Ingest::DeterministicRules

**Status:** OPEN
**Created:** 2026-08-07T02:38:22Z
**Updated:** 2026-08-07T02:45:59Z
**Author:** Robert Pannick (@b08x)
**URL:** https://github.com/b08x/sfl-engine/issues/47

## Description

Part of the [Intelligent Ingest Layer plan](docs/superpowers/plans/2026-08-06-intelligent-ingest-layer.md) (Task 5 of 10).

## Goal
Add `Ingest::DeterministicRules`, the free/instant fast-path classifier consulted before `Core::Ports::Classifier`.

## Files
- Create: `lib/sfl/ingest/deterministic_rules.rb`
- Test: `spec/ingest/deterministic_rules_spec.rb`

## Interfaces
- Consumes: `Analysis::ChatExportExpander.detect_format` (`lib/sfl/analysis/chat_export_expander.rb:37`), `Analysis::KnowledgeBaseSource::TEXT_EXTENSIONS`/`IMAGE_EXTENSIONS` (`lib/sfl/analysis/knowledge_base_source.rb:53-54`).
- Produces: `Ingest::DeterministicRules.classify(path) -> {format:, mode:, source_type:} | nil`. Consumed by Task 9 (`Ingest::Orchestrator`).

**Note (documented deviation from the approved spec):** returns `source_type:` instead of the spec's sketched `loader_class:` key — the three existing target engines already do their own internal loader dispatch, so a `loader_class:` key would be redundant. See the plan's Task 5 "Design note" for full rationale.

## Checklist
- [ ] Write the failing spec
- [ ] Verify it fails
- [ ] Write the implementation
- [ ] Verify it passes
- [ ] Rubocop
- [ ] Commit

Full code is in the plan document, Task 5 section.

## Labels

None

## Assignees

None
