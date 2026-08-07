# Issue #45: Task 3: Core::Types::ClassificationResult

**Status:** OPEN
**Created:** 2026-08-07T02:38:20Z
**Updated:** 2026-08-07T02:45:57Z
**Author:** Robert Pannick (@b08x)
**URL:** https://github.com/b08x/sfl-engine/issues/45

## Description

Part of the [Intelligent Ingest Layer plan](docs/superpowers/plans/2026-08-06-intelligent-ingest-layer.md) (Task 3 of 10).

## Goal
Add the `Core::Types::ClassificationResult` Dry::Struct type.

## Files
- Create: `lib/sfl/core/types/classification_result.rb`
- Test: `spec/core/types/classification_result_spec.rb`

## Interfaces
`Core::Types::ClassificationResult.new(format:, mode:, confidence:, reasoning:)`:
- `format: Core::Types::String`
- `mode: Core::Types::String.optional`
- `confidence: Core::Types::Coercible::Float.constrained(gteq: 0.0, lteq: 1.0)`
- `reasoning: Core::Types::String`

Consumed by Task 4 (`Core::Ports::Classifier`), Task 6 (`LLM::Classifier`), Task 9 (`Ingest::Orchestrator`).

`format`/`mode` are plain `String`, not `Symbol` — matches `InterpersonalPayload#mood`/`TextualPayload#theme_type` storage conventions.

## Checklist
- [ ] Write the failing spec
- [ ] Verify it fails
- [ ] Write the implementation
- [ ] Verify it passes
- [ ] Rubocop
- [ ] Commit

Full code is in the plan document, Task 3 section.

## Labels

None

## Assignees

None
