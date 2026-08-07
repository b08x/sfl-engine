# Issue #50: Task 8: Ingest::LoaderDrafter

**Status:** OPEN
**Created:** 2026-08-07T02:38:25Z
**Updated:** 2026-08-07T02:46:02Z
**Author:** Robert Pannick (@b08x)
**URL:** https://github.com/b08x/sfl-engine/issues/50

## Description

Part of the [Intelligent Ingest Layer plan](docs/superpowers/plans/2026-08-06-intelligent-ingest-layer.md) (Task 8 of 10).

## Goal
Add `Ingest::LoaderDrafter`, which drafts a candidate loader for genuinely unrecognized file formats, plus its schema and prompt template.

## Files
- Create: `lib/sfl/llm/schemas/loader_draft_schema.rb`
- Create: `lib/sfl/prompts/templates/loader_drafting.txt.erb`
- Create: `lib/sfl/ingest/loader_drafter.rb`
- Test: `spec/ingest/loader_drafter_spec.rb`

## Interfaces
- Consumes: `Core::Loaders::Source` mixin contract (`lib/sfl/core/loaders/source.rb`), `Prompts.render`, `ResponseSymbolizer`.
- Produces: `Ingest::LoaderDrafter.new(chat:, loaders_dir: "lib/sfl/core/loaders", docs_dir: "docs/ingest-review")`, `#draft(sample, path) -> {loader_path:, doc_path:}`, raising `Ingest::LoaderDrafter::Error` on an LLM/schema failure (caught by Task 9's `Orchestrator`, which records `status: "draft_failed"`). Consumed by Task 9.

**Safety boundary:** never requires, registers, or executes the drafted file — it's written inert; a human must review it and manually wire it in.

## Checklist
- [ ] Write the schema
- [ ] Write the prompt template
- [ ] Write the failing spec
- [ ] Verify it fails
- [ ] Write the implementation
- [ ] Verify it passes
- [ ] Rubocop
- [ ] Commit

Full code is in the plan document, Task 8 section.

## Labels

None

## Assignees

None
