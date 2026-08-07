# Issue #48: Task 6: LLM::Classifier (real Core::Ports::Classifier adapter)

**Status:** OPEN
**Created:** 2026-08-07T02:38:23Z
**Updated:** 2026-08-07T02:46:00Z
**Author:** Robert Pannick (@b08x)
**URL:** https://github.com/b08x/sfl-engine/issues/48

## Description

Part of the [Intelligent Ingest Layer plan](docs/superpowers/plans/2026-08-06-intelligent-ingest-layer.md) (Task 6 of 10). Depends on Tasks 3-4.

## Goal
Add `LLM::Classifier`, the real `Core::Ports::Classifier` adapter, plus its structured-output schema and prompt template.

## Files
- Create: `lib/sfl/llm/schemas/classification_schema.rb`
- Create: `lib/sfl/prompts/templates/ingest_classification.txt.erb`
- Create: `lib/sfl/llm/classifier.rb`
- Test: `spec/llm/classifier_spec.rb`

## Interfaces
- Consumes: `Core::Ports::Classifier` (Task 4), `Core::Types::ClassificationResult` (Task 3), `Prompts.render` (`lib/sfl/prompts.rb:19`), `LLM::ResponseSymbolizer.call` (`lib/sfl/llm/response_symbolizer.rb:10`), `Core::Ports::Breaker`/`Null::Breaker`, `Core::Ports::Logger`/`Null::Logger`.
- Produces: `LLM::Classifier.new(chat:, breaker: Core::Ports::Null::Breaker.new, logger: Core::Ports::Null::Logger.new)`, `#classify(sample, path) -> Core::Types::ClassificationResult`. A failed/timed-out call degrades to a confidence-0.0 "unknown" result rather than raising. Consumed by Task 7 (`Boot.build_classifier`) and Task 9.

## Checklist
- [ ] Write the schema
- [ ] Write the prompt template
- [ ] Write the failing spec
- [ ] Verify it fails
- [ ] Write the implementation
- [ ] Verify it passes
- [ ] Rubocop
- [ ] Commit

Full code is in the plan document, Task 6 section.

## Labels

None

## Assignees

None
