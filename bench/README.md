# bench/

Perf-skill discipline (track decision 5): nothing in this codebase is "optimized" until a
profile names the hotspot and a committed benchmark shows a >=10-20% win. This directory is
the harness that makes that claim checkable.

## Status

- `pipeline_bench.rb` — **implemented**. Wall-clock + peak-RSS harness (`/usr/bin/time -v`
  around a `sfl-analyze` CLI invocation), emits a YAML record to `results/`. Must be run from
  *inside* the repo being benchmarked — see the file's header comment for why (asdf per-directory
  Ruby version resolution doesn't survive a cross-directory subprocess spawn in this environment).
- `store_bench.rb` — not yet implemented. `replace_document` with 500 clauses, benchmark-ips,
  old per-clause-transaction loop vs `multi_insert` (Phase 2).
- `retrieval_bench.rb` — not yet implemented. Seeded pg with a large clause set; filtered vs
  unfiltered retrieve (Phase 2).

## Baseline capture — done (stub mode only)

`results/legacy-baseline-conversation.yml` was captured 2026-07-24 against the legacy repo's
`conversation` subcommand in `--pass1-only` (stub) mode — no LLM cost. It's a small-fixture
number (5 turns / 8 clauses) dominated by fixed process-boot cost (Ruby + spaCy/PyCall model
load), so `clauses_per_min` here is **not** a steady-state throughput figure — re-run against
a production-shaped corpus per blueprint §4.1 once one exists. A real-Pass-2 baseline (LLM
calls/doc, actual annotation latency) has not been captured; the `documentation` subcommand
run during golden-master capture is the only real-LLM data point on hand so far, and it's
tainted by the `--pass1-only` bug in track decision 13 (not a clean baseline).
