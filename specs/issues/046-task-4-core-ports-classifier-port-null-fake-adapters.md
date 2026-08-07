# Issue #46: Task 4: Core::Ports::Classifier port + Null/Fake adapters

**Status:** OPEN
**Created:** 2026-08-07T02:38:21Z
**Updated:** 2026-08-07T02:45:58Z
**Author:** Robert Pannick (@b08x)
**URL:** https://github.com/b08x/sfl-engine/issues/46

## Description

Part of the [Intelligent Ingest Layer plan](docs/superpowers/plans/2026-08-06-intelligent-ingest-layer.md) (Task 4 of 10). Depends on Task 3.

## Goal
Add the `Core::Ports::Classifier` port plus `Null`/`Fake` adapters.

## Files
- Create: `lib/sfl/core/ports/classifier.rb`
- Create: `lib/sfl/core/ports/null/classifier.rb`
- Create: `lib/sfl/core/ports/fake/classifier.rb`
- Modify: `spec/support/shared_examples/ports.rb` (add "a classifier port" shared example)
- Modify: `spec/core/ports/null_adapters_spec.rb` (add `Null::Classifier` block)
- Modify: `spec/core/ports/fake_adapters_spec.rb` (add `Fake::Classifier` block)

## Interfaces
- Consumes: `Core::Types::ClassificationResult` (Task 3).
- Produces:
  - `Core::Ports::Classifier` module with `#classify(sample, path) -> Core::Types::ClassificationResult`
  - `Null::Classifier.new` — always returns `format: "unknown", mode: nil, confidence: 0.0, reasoning: "..."`
  - `Fake::Classifier.new(results: {})` — returns a caller-registered `ClassificationResult` per exact `sample` string, or a low-confidence default

Consumed by Task 6 (`LLM::Classifier` includes this port) and Task 9 (`Ingest::Orchestrator`).

## Checklist
- [ ] Write the failing specs (shared example + Null + Fake)
- [ ] Verify they fail
- [ ] Write the port
- [ ] Write the Null adapter
- [ ] Write the Fake adapter
- [ ] Verify specs pass
- [ ] Rubocop
- [ ] Commit

Full code is in the plan document, Task 4 section.

## Labels

None

## Assignees

None
