# Issue #49: Task 7: SFL::Boot wiring - ingest_classification + loader_drafting task configs

**Status:** OPEN
**Created:** 2026-08-07T02:38:24Z
**Updated:** 2026-08-07T02:46:01Z
**Author:** Robert Pannick (@b08x)
**URL:** https://github.com/b08x/sfl-engine/issues/49

## Description

Part of the [Intelligent Ingest Layer plan](docs/superpowers/plans/2026-08-06-intelligent-ingest-layer.md) (Task 7 of 10). Depends on Task 6.

## Goal
Wire two new `SFL::Boot` task configs (`ingest_classification`, `loader_drafting`) and expose `Boot::Result#classifier`.

## Files
- Modify: `lib/sfl/boot.rb:50` (`TASK_NAMES`), `:155-181` (`call`), `:184-193` (`build_llm_collaborators`), `:206-216` (`build_llm_config`)
- Modify: `lib/sfl/boot/result.rb` (add `:classifier` to the `Result` Struct)
- Test: `spec/boot/boot_spec.rb` (add examples for the two new tasks + `Boot::Result#classifier`)

## Interfaces
- Consumes: `LLM::Classifier` (Task 6), `task_config_from_env` (unchanged).
- Produces: `Boot::Result#classifier -> LLM::Classifier`, plus `llm_config.for(:ingest_classification)`/`llm_config.for(:loader_drafting)` become valid calls.

**Design note:** `ingest_classification` defaults to the same provider/model as `:embedding` (cheap tier). `loader_drafting` defaults to the same default as `:pass_two_annotation` (stronger general-purpose model). Both overridable via `SFL_TASK_INGEST_CLASSIFICATION_MODEL/_PROVIDER` and `SFL_TASK_LOADER_DRAFTING_MODEL/_PROVIDER` env vars.

## Checklist
- [ ] Read `lib/sfl/boot.rb` and `spec/boot/boot_spec.rb` in full
- [ ] Write the failing spec additions
- [ ] Verify they fail
- [ ] Update `TASK_NAMES`
- [ ] Add the two task configs to `build_llm_config`
- [ ] Build the `LLM::Classifier` collaborator and expose it on `Boot::Result`
- [ ] Verify specs pass
- [ ] Rubocop
- [ ] Commit

Full code is in the plan document, Task 7 section.

## Labels

None

## Assignees

None
