# SFL Engine TUI — Rework Design

**Date:** 2026-08-29
**Status:** Approved for planning
**Code lands in:** `/home/b08x/WorkspaceV3/sfl-engine`
**Supersedes:** `docs/tui-implementation-plan.md` §2 (workspace set), §5 (build order), §6–§7
**Companion spec:** [Vault Annotation Substrate](2026-08-29-vault-annotation-substrate-design.md)

---

## Why rework rather than continue

The existing plan is a careful document — every gem verified against its repo rather
than assumed, honest that `bubbletea` is a pre-1.0 single-maintainer port. Its
**mechanics** are sound and kept wholesale. Its **workspace set** is not.

The four workspaces were reverse-fitted from a supplied mockup ("Other Steve v2.0"), a
generic AI-pair-debugging cockpit concerned with nginx 502s and arxiv triage. The plan
re-derives each tab against real capabilities and concedes the seams itself: §2.3 is
*"the weakest fit of the four and the most speculative"*, and §2.4 is a trackboi Kanban
board — project management for sfl-engine's *developers*, not a job of a corpus tool.

Two further changes since it was written:

- The substrate spec runs **fully local by default**. An LLM is opt-in for dataset
  production only.
- **Agent chat / RAG Q&A is an explicit non-goal**, deferred to a possible separate
  plugin. That removes the Query Console.

### Inherited findings, not up for redecision

| Finding | Consequence |
|---|---|
| `huh` is **not on RubyGems** | Any command palette is built on `bubbles::TextInput` + a custom completion list. No `git:` Gemfile source. |
| `bubbletea` is pre-1.0, single-maintainer | Verify every gem API against installed source. `program.rb` records a case where the old plan assumed an API that did not exist and *"would fail at the first message."* |
| Phase 0/1 shipped | Root `Program` MVU router, `Alt+1..n`, `Layout`, `Theme`, `Messages`, `SafeCommand`, workspace `Base` all exist and are kept. |

The old plan's finding that DSPy cannot stream is now moot — the pane it constrained
(Query Console) is cut.

---

## Verified gem findings

Both read directly from `bubbletea-0.1.4`'s installed source.

### `$EDITOR` handoff works

`Runner#exec_process` implements full `tea.ExecProcess` semantics:

```ruby
@program.disable_mouse …; @program.show_cursor
@program.stop_input_reader; @program.exit_raw_mode
command.callable.call                       # external editor owns the terminal
@program.enter_raw_mode; @program.hide_cursor
@program.start_input_reader; @program.enable_mouse…
handle_message(command.message) if command.message
```

`Bubbletea.exec(callable, message:)` releases the terminal, runs the editor
synchronously, restores raw mode, and dispatches a completion message.

**Open detail for the spike:** `exec_process` does not touch alt-screen state
(`@in_alt_screen` is untouched). If the TUI is in alt screen and the editor enters its
own, verify the pop-back on the target terminal.

### Background threads must NOT call `Runner#send`

This settles the old plan's §4 point 2.

```ruby
def send(message)
  @pending_messages ||= []     # plain Array — no mutex
  @pending_messages << message
end
```

The `Proc` command branch does `Thread.new { … send(result) }`, so background threads
append to an unsynchronised array. It will appear to work at low message rates, which
is the dangerous kind of broken.

**Mandated pattern for any pane with background work:** the worker writes to the
workspace's own `Queue`; a `Bubbletea.tick` drains it **on the main loop** and folds
results into model state. Never call `send` from a worker thread.

---

## Architecture — unchanged

The Phase 1 shell is correct and is built on, not replaced.

- **`Program` is the only `Bubbletea::Model`** — real arities `init/0`, `update/1`,
  `view/0`, closing over its `AppContext`. Workspaces take context explicitly:
  `init/1`, `update/2`, `view/1`.
- **Workspaces return new instances**, never mutate. Where a `bubbles` sub-model is
  embedded (it mutates in place and returns `[self, cmd]`), the wrapping component
  reconciles the conventions rather than leaking mutation upward.
- **Every command returns a SINGLE command or nil** — combine with
  `Bubbletea.batch`/`sequence`.
- **Every command goes through `SafeCommand`.** A raising Proc is swallowed by the
  runner *after* its backtrace is smeared across the frame — the app appears to hang
  with a corrupted display and nothing logged. `SafeCommand` unwraps a `Dry::Monads`
  `Failure` into `Messages::Failed`, the single failure channel, whose detail is
  whitespace-collapsed so a multi-line PG error cannot become a multi-row status bar.
- **Never `StderrLogger`** — a background `$stderr.puts` lands inside the rendered
  frame and breaks the renderer's cursor arithmetic (Phase 0 finding).
- **`Layout.columns` guarantees widths sum to exactly the available width**, because
  `join_horizontal` on an over-wide row wraps the frame.
- **`Ctrl+C` maps to `Bubbletea.quit` unconditionally**, before workspace delegation —
  bubbletea-ruby installs no SIGINT handler, and missing it strands the terminal in raw
  mode inside the alt screen.

### No Boot widening required

`AppContext` is built under
`Boot.call(require_db: true, require_llm: false, require_tracing: false)`, so
`lm_factory`, `embedder` and `classifier` are `nil`. The previous draft made widening
this a prerequisite — **it no longer is.** Every workspace below is local-only. Boot
stays as it is, and the TUI never needs an API key.

---

## The workspace set

| # | Workspace | Backed by | Status |
|---|---|---|---|
| 1 | **Triage** | `PgReviewQueueRepository`, `PgAnnotationReviewRepository`, `contradictions` | reworked from §2.2 — build first |
| 2 | **Ingest Monitor** | `Nexo::Workflow`, `checkpoint_all` | new |
| 3 | **Concept Map** | gap clustering, `PgClauseStore` | replaces §2.3; deferred |
| — | ~~Query Console~~ | ~~`ContextSynthesizer`~~ | **cut** — agent chat is a non-goal |
| — | ~~Board~~ | ~~`.trackboi/*`~~ | **cut** |

Cutting both panes removes `ruby_llm-mcp`, `bubblezone`, `glamour` and `harmonica` from
the plan. It also resolves a live inconsistency in the old document: §3 argues adopting
`ruby_llm-mcp` *"would mean running two different LLM client stacks side by side for no
reason"*, while §2.4/§6/§7 adopt it anyway; §3's text was never updated. The
contradiction disappears with the pane.

---

## Workspace 1 — Triage

**The reason to build a TUI at all**, and it now serves both consumers: contradiction
adjudication *and* dataset curation. The HITL flow that upgrades `annotation_source`
from `llm` to `human` is exactly how a platinum eval set gets made. The old plan's
judgement holds — a keyboard-driven terminal interface is *"arguably the better
interface for this job than a browser."*

**The rework:** the old plan had content review and annotation review as two
tab-switchable queues; contradictions would make three. Instead there is **one queue
with a source filter** — `content` · `annotation` · `contradiction` — because the
operator's motion is identical in all three: look, judge, move on. Three screens with
one verb is a worse interface than one screen with three filters.

**Layout** — three panes at 30 / 45 / 25:

| Pane | Content |
|---|---|
| Queue | `bubbles::List` of pending items; status glyph, source-type badge, document label |
| Detail | Content: extracted text + source file. Annotation: tokens, ideational payload, interpersonal payload, `annotation_source`. Contradiction: both clauses side by side with their ideational payloads |
| Diff / Evidence | Annotation: before/after `mood` · `tenor` · `modality_weight` as `ntcharts` bars. Contradiction: NLI score, modality delta, and the retrieval path that surfaced the pair |

**Keys:** `j`/`k` navigate · `1`/`2`/`3` filter by source · `a` accept · `r` reject ·
`n` re-annotate · `e` edit · `?` help. Single-key decisions, no modal confirmation
except reject.

**Provenance is displayed, not hidden.** The operator must be able to see whether an
interpersonal payload came from `rules`, `llm`, or `human` before judging it — a
rules-derived `tenor` is `nil` by design, and a reviewer needs to know that is correct
rather than missing data.

**Writes** go to the repositories in-process via
`#decide(id:, decision:, edited_text:, reviewer:)`. Contradiction verdicts additionally
set `contradictions.status`; a rejected contradiction is recorded, never deleted, so a
re-sweep after recalibrating the modality floor cannot resurface a dismissed item.

## Workspace 2 — Ingest Monitor

Batch ingest currently runs blind. This is the only surface for a `Nexo::Workflow`
crossing ~700 attachments.

| Pane | Content |
|---|---|
| Run summary | Run id, elapsed, counts by state — pending / extracting / annotating / done / failed |
| File list | Per-attachment state; failures sorted first with reason |
| Detail | Pairing strategy and confidence, resolved `Source` class, checkpoint state, error text |

**Concurrency is the whole design problem**, constrained by the `send` finding:

- The workflow runs on a worker thread and writes progress to a plain `Queue`.
- The workspace issues a repeating `Bubbletea.tick` (~250 ms) whose handler drains that
  queue on the main loop.
- Nothing but the main loop touches model state or `Runner#send`.

**Actions:** `s` start a run over a chosen root · `x` request stop (cooperative, via the
`TUI::StopFlag` that already exists) · `R` resume a run by id — `checkpoint_all` re-runs
only incomplete tasks.

## Workspace 3 — Concept Map *(deferred)*

Replaces the Corpus Browser. §2.3's problem was having no backend; gap clustering is
that backend.

| Pane | Content |
|---|---|
| Clusters | Topics by representative terms, with document counts |
| Members | Clauses in the selected cluster, with source attribution |
| Outliers | HDBSCAN `-1` and low-density members — **the gaps** |

Topics are listed by **representative terms and centroid, never by index** — UMAP is
stochastic and indices are not stable across runs. A pane keyed on topic number would
silently show the wrong cluster after a re-fit.

`f` filters · `e` drafts a stub note from the selection · `Enter` drills in.

**Deferred behind the other two.** It depends on the last component of the substrate
spec, and it should be designed against real clusters rather than imagined ones.

---

## Editing: `$EDITOR` handoff, no built-in editor

`bubbles::TextArea` exists; building an editor on it was considered and rejected.
Instead `e` hands the terminal to `$EDITOR` (`micro` here):

```ruby
Bubbletea.exec(
  -> { system(ENV.fetch("EDITOR", "micro"), path) },
  message: Messages::EditorClosed.new(path)
)
```

Two targets, deliberately different in kind:

**1. Extracted text (Triage).** Correct a garbled transcription. Written to a temp file,
edited, read back on `EditorClosed`, saved to `review_queue.generated_text`, then
recompiled. Parity with the Glimmer GUI's existing `SaveAndRecompileSection`, which
edits the same field. **No vault file is touched.**

**2. Stub notes (Concept Map).** A gap becomes a **new** markdown file — frontmatter,
the clauses evidencing the gap, backlinks to sources — written to a staging directory,
then opened for write-up.

**The safety property: the TUI never edits an existing vault file.** `sfl-engine` has
never written to a source corpus — every `File.write` in `lib/` produces a derived
output. New-file-only preserves that boundary and structurally eliminates the
concurrent-edit hazard: the vault is live in Obsidian, and an unsaved Obsidian buffer
wins on its next save, silently clobbering an external edit. There is no such conflict
for a file Obsidian has never opened.

Obsidian remains the editor for existing notes. It is better at it than anything built
in `bubbles::TextArea`.

---

## Error handling

- **Every command through `SafeCommand`** — a raising Proc corrupts the frame and logs
  nothing.
- **`Messages::Failed` is the only failure channel**, rendered as explicit state in the
  status bar; detail whitespace-collapsed to protect the single-row structure.
- **Terminal below 40×10** — `Layout` clamps rather than emitting negative widths; the
  pane shows a "terminal too small" state.
- **Editor exits non-zero or file unchanged** — the edit is discarded, the item left
  untouched. Never a partial write.

## Testing

Every workspace is a plain object with `init/1`, `update/2`, `view/1` — constructed with
fake ports, fed messages, asserted on state. No terminal is booted. This is the shape
`ReviewQueueViewModel` specs already use.

- **`Layout`** — pure arithmetic; columns sum to exactly the available width across a
  range of sizes, including the clamped minimum.
- **Triage** — each filter's item set; a rejected contradiction stays rejected across a
  re-sweep; provenance is rendered for every item.
- **Ingest Monitor** — the load-bearing test: a tick drains a pre-loaded queue and folds
  events into state, and no code path calls `send` off the main loop.
- **Editing** — fake editor command; assert the unchanged-file and non-zero-exit paths
  discard cleanly.

## Build order

| Phase | Scope | Depends on |
|---|---|---|
| A | **Triage** — one queue, content + annotation filters, `$EDITOR` handoff | nothing new |
| B | **Ingest Monitor** — tick-drained queue over `Nexo::Workflow` | substrate steps 1–4 |
| C | Triage gains the **contradiction** filter | substrate step 5 |
| D | **Concept Map** | substrate step 7 |

A is first and depends on nothing from the substrate spec: it delivers standalone value
against data the store already holds, and validates the repository-write path end to
end.

## Open questions for implementation

- Alt-screen pop-back when `$EDITOR` enters its own alt screen (spike).
- Tick interval for the Ingest Monitor — 250 ms is a starting guess, tuned against a
  real batch.
- Whether the stub-note staging directory is configurable or fixed under the vault root.
