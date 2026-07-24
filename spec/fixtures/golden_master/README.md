# Golden-master fixtures (Phase 0)

Captured 2026-07-24 by running the **legacy** repo's CLI
(`/home/b08x/WorkspaceV3/sfl-compiler`) against `spec/fixtures/inputs/`. These are the
characterization fixtures the rebuild's output is diffed against (allowing for the F4-class
fix, which is an intentional documented output change — see Phase 3).

## conversation/ — clean baseline

```
bundle exec exe/sfl-analyze conversation spec/fixtures/conversations/sample.jsonl \
  --output-dir <out> --pass1-only --disable-tracing --topics 3
```

`--pass1-only` worked as expected here: `annotation_coverage.llm == 0`, all 8 clauses
DEFAULTED/stubbed. No LLM calls, no cost. This is the deterministic baseline.

## documentation/ — NOT clean, real LLM calls were made

```
bundle exec exe/sfl-analyze documentation spec/fixtures/docs/sample.md \
  --output-dir <out> --pass1-only --disable-tracing --topics 3
```

**`--pass1-only` did not suppress Pass 2 annotation for the `documentation` subcommand** —
the output shows `annotation_coverage.llm == 6` (6/6 clauses really annotated, real API
calls, real cost), unlike `conversation` which correctly stayed stub-only. This is a
discrepancy between subcommands worth a Five-Whys pass during Phase 1/3 porting (why does
`--pass1-only` gate one analyzer's Pass 2 call but not the other's — likely one of the
~350 duplicated lines the D2/F4 unification is meant to end). Kept anyway since it was
already paid for and is a real reference for actual system behavior, but it is **not** a
byte-exact diffable baseline the way `conversation/` is — re-running it will not reproduce
identical output (LLM non-determinism), and `analyzed_at` timestamps differ on every run in
both fixture sets regardless.

## Diffing notes

- Exclude `metadata.analyzed_at` (and any other wall-clock timestamp) from comparisons —
  it is never stable across runs.
- `conversation/` should be byte-stable modulo the F4 rounding fix; treat any other diff as
  a regression.
- `documentation/` is a reference, not a regression gate, until the `--pass1-only` gap above
  is understood and the fixture is regenerated in stub mode.
