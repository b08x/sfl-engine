# Review Queue GUI — Design

**Date:** 2026-08-06
**Status:** Approved (design phase) — not yet implemented

## Problem

`Store::PgReviewQueueRepository` and its `review_queue` table (`db/migrations/007_create_review_queue.rb`)
already track content flagged for human review — low-quality/fallback Pass 2 annotations
(`lib/sfl/analysis/knowledge_base_source.rb:263-284`) and vision-model image descriptions
(`source_type == "vault_image"`) — but there is no UI for this workflow at all. It is
manipulated by hand via `psql` or ad hoc Ruby. This is sfl-engine's first GUI.

## Goals

- A Glimmer DSL for LibUI desktop app that lists pending `review_queue` rows across all three
  modalities (image/text/audio), lets a reviewer inspect each one (rendering the source image
  inline for image rows), and record a decision.
- **Approve**: records the decision only (`PgReviewQueueRepository#decide`) — the content is
  already correctly stored, nothing else to do.
- **Reject**: records the decision only, per this design's scope decision — clauses stay stored
  as originally compiled; a human handles any further cleanup manually outside this app.
- **Edit-and-recompile**: a reviewer can correct the flagged text (or image description) and
  have it actually take effect — re-run through `Core::Pipeline#compile` for that
  `document_id`, replacing the previously-stored clauses/embeddings, not just recording an
  audit note.
- Auto-refresh (10s timer) so the list reflects new pending rows without a manual action, while
  never clobbering a reviewer's in-progress selection/edit.

## Non-goals

- Any UI for the separate, unrelated `PgAnnotationReviewRepository` flow (Pass 2
  confidence review) — out of scope for this app, could be a second screen later.
- Any UI for the `ingest_review_entries` table from the (separately planned, not yet
  implemented) Intelligent Ingest Layer — this app only wraps `review_queue`.
- Deleting/clearing stored clauses on Reject — deliberately deferred per the scope decision
  above.

## Architecture

```
exe/sfl-review
        │
        ▼
SFL::GUI::ReviewQueueApp (root window)
  owns: ReviewQueueViewModel (repo + pipeline + reviewer_name)
  timer (every 10s, UI thread) → viewmodel.refresh!
        │
        ├── ItemListControl(viewmodel:)       [left pane]
        │     modality filter combobox + table, bound to viewmodel.items
        │     on_row_clicked → viewmodel.select(row)
        │
        └── DetailPaneControl(viewmodel:)     [right pane]
              metadata labels (modality/reason/source_file/created_at)
              ├── ImageReviewControl(viewmodel:)   visible when modality == "image"
              │     image(source_file) + multiline_entry <=> edited_text + "Save & Recompile"
              ├── TextReviewControl(viewmodel:)    visible when modality in [text, audio]
              │     multiline_entry <=> edited_text + "Save & Recompile"
              └── Approve / Reject buttons (shared, modality-agnostic)
```

`ReviewQueueViewModel` is the only class touching `PgReviewQueueRepository`/`Core::Pipeline` —
every control reads/writes it via data-binding, never the repo/pipeline directly. This is the
Approach C decomposition (separate class-based custom control per responsibility), chosen over
a single flat class so each control is independently understandable, and over method-based
controls so the pieces are reusable/testable across files, matching the `ruby-dev:gui` skill's
"promote to class-based when used across files/views" guidance.

**Verified against the `ruby-dev:gui` skill's reference docs before finalizing this design:**
Glimmer doesn't document swapping which custom-control *class* renders based on a changing
value — the safe, verified pattern is keeping both modality controls always present in the tree
and toggling their `visible` property (a documented common property, bindable via `<=` the same
way `text`/`enabled` already are elsewhere in this design). `image(file_path, width, height)` is
a confirmed real keyword (`references/controls-cheatsheet.md`), usable inside `area`.

## Components

### `SFL::GUI::ReviewQueueViewModel` (plain Ruby, the model layer — no Glimmer include)

```ruby
attr_accessor :items, :selected_item, :modality_filter, :edited_text
```

- `initialize(repo:, pipeline:, reviewer_name:)` — `repo` is `Store::PgReviewQueueRepository`,
  `pipeline` is `Core::Pipeline` (built once at launch via `Boot.call`, same as
  `SFL::CLI.build_pipeline`). `reviewer_name` is read from `ENV["SFL_REVIEWER_NAME"]` by the
  app at launch, not by this class — Boot/the app entry point stays the only ENV reader (track
  decision 4), this class takes it as an injected plain String.
- `#refresh!` — re-queries `repo.pending(modality: modality_filter == "all" ? nil : modality_filter)`,
  reassigns `items` (not mutated in place — matches the observer-notification rule every bound
  collection in this codebase's Glimmer views follows). **Preserves selection**: if
  `selected_item`'s `id` is still present in the new result set, keeps it selected (and leaves
  `edited_text` untouched); otherwise clears `selected_item`/`edited_text` (the row was resolved
  elsewhere, by this app or another process).
- `#select(item)` — sets `selected_item = item`, seeds `edited_text = item[:generated_text]`.
- `#approve!` — `repo.decide(id: selected_item[:id], decision: "approve", reviewer: reviewer_name)`,
  then `refresh!`.
- `#reject!` — `repo.decide(id: selected_item[:id], decision: "reject", reviewer: reviewer_name)`,
  then `refresh!`. Only flips status; clauses stay stored as originally compiled (scope
  decision above).
- `#save_and_recompile!` — calls `pipeline.compile(edited_text, document_id: selected_item[:document_id],
  store: true, embed: true)` **first**. Only on `Success` does it call `repo.decide(decision: "edit",
  reviewer: reviewer_name)` and `refresh!`. On `Failure`, returns the failure to the caller — the
  row stays `pending`, nothing is marked edited on a failed recompile, `edited_text` is
  preserved so the reviewer can retry.
- Errors from `repo.pending`/`repo.decide` (e.g. `Sequel::Error` on a dropped DB connection) are
  caught once, centrally, in these four methods and converted to a return value the calling
  control turns into a dialog — never an uncaught exception reaching the LibUI event loop.

### `SFL::GUI::ReviewQueueApp` (`include Glimmer::LibUI::CustomWindow`, the composition root)

Builds `Boot.call(require_llm: true, require_tracing: false)` once at launch —
`require_tracing: false` unconditionally, since `LangfuseReachability.decide`'s reachability
prompt expects an interactive tty (`lib/sfl/boot/langfuse_reachability.rb`), which a GUI process
doesn't have in the CLI's sense. Builds `Core::Pipeline` by reusing `SFL::CLI.build_pipeline`'s
existing wiring (not duplicating it). Owns `Glimmer::LibUI.timer(10) { view_model.refresh! }` —
runs on the UI thread already (per the `ruby-dev:gui` skill), so no `queue_main` wrapping is
needed around this particular call.

### `SFL::GUI::ItemListControl` (class-based, `options :viewmodel`)

A `combobox` (`items ['all', 'image', 'text', 'audio']`) bound one-way into
`viewmodel.modality_filter`, triggering `viewmodel.refresh!` on `on_selected`. Below it, a
`table` with `text_column`s for modality/reason/source_file/created_at, `cell_rows <= [viewmodel,
:items]` (one-way — the table never writes back), `on_row_clicked { |row| viewmodel.select(viewmodel.items[row]) }`.

### `SFL::GUI::DetailPaneControl` (class-based, `options :viewmodel`)

`vertical_box` (single root, per Glimmer's "`body` needs exactly one root control" rule)
containing: labels for the selected item's modality/reason/source_file/created_at (blank when
nothing is selected), then `image_review_control(viewmodel:)`, then
`text_review_control(viewmodel:)`, then the shared `button('Approve')`/`button('Reject')` pair —
each `on_clicked` calling `viewmodel.approve!`/`viewmodel.reject!`, both `enabled <= [viewmodel,
:selected_item, on_read: ->(item) { !item.nil? }]`.

### `SFL::GUI::ImageReviewControl` (class-based, `options :viewmodel`)

Root box `visible <= [viewmodel, :selected_item, on_read: ->(item) { item&.dig(:modality) ==
"image" }]`. Inside: `area { image(viewmodel.selected_item&.dig(:source_file), 400, 400) }`
above a `multiline_entry { text <=> [viewmodel, :edited_text] }`, then `button('Save & Recompile')`
calling `viewmodel.save_and_recompile!` and showing `msg_box_error` on a `Failure` result.

### `SFL::GUI::TextReviewControl` (class-based, `options :viewmodel`)

Same shape minus the image: `visible` bound to modality being `"text"` or `"audio"`,
`multiline_entry <=> edited_text`, `button('Save & Recompile')`. Serves both text and audio
modalities identically — audio has no special rendering need beyond the transcript text itself
(and per the design discussion, no audio-modality `enqueue` call site exists in the codebase
yet, so audio rows won't appear in practice until one is added elsewhere).

### `exe/sfl-review`

New binstub, mirrors `exe/sfl-analyze`'s shebang/require pattern, calls
`SFL::GUI::ReviewQueueApp.launch`.

## Data Flow — two worked examples

**Approve (the simple path):** reviewer clicks a row in `ItemListControl` → `on_row_clicked`
calls `viewmodel.select(row)` → `DetailPaneControl`'s labels and the modality-specific control's
`visible` bindings react automatically (no explicit refresh call needed) → `ImageReviewControl`
or `TextReviewControl` becomes visible, `edited_text` shows the current `generated_text` →
reviewer clicks **Approve** → `viewmodel.approve!` → `repo.decide(decision: "approve")` →
`viewmodel.refresh!` re-queries `pending`, the approved row drops out of the result set,
`selected_item` clears since that row is gone, both modality controls go invisible again.

**Edit-and-recompile (the case that touches the pipeline):** reviewer selects an
`image`-modality row → `ImageReviewControl` becomes visible, shows the flagged image inline plus
the vision model's description in the editable text area → reviewer corrects a mistake in the
description, clicks **Save & Recompile** → `viewmodel.save_and_recompile!` calls
`pipeline.compile(edited_text, document_id: selected_item[:document_id], store: true, embed:
true)` — the **same** `Core::Pipeline#compile` every other entry point uses, so
`PgClauseStore#replace_document`/`PgEmbeddingStore#replace_document`'s existing idempotent
delete+reinsert (the F7 fix) transparently replaces that document's previously-flagged clauses
with freshly-compiled ones from the corrected text — no new storage logic anywhere. On
`Success`, `repo.decide(decision: "edit")` records the audit trail and `refresh!` drops the row
from `pending`. On `Failure` (e.g. the LLM call fails), the control shows `msg_box_error(title,
failure.inspect)`, the row stays `pending`, `edited_text` keeps the reviewer's correction so
nothing is lost on retry.

**Auto-refresh interacting with an in-progress edit:** the 10s timer fires while a reviewer has
an image selected and has started editing its text. `refresh!` re-queries `pending`; since that
row's `id` is still present in the fresh result set (it hasn't been decided yet), `selected_item`
and `edited_text` are left untouched — the reviewer's in-progress edit survives a background
refresh. Only a row that *disappears* from the new result set (resolved by this or another
process) clears the selection.

## Error Handling

- **`pipeline.compile` failure** (LLM error, DB error) — never raised past
  `save_and_recompile!`'s caller as an exception the GUI has to rescue ad hoc; `Pipeline#compile`
  already returns a `Dry::Monads::Result`, so this is just checking `.success?`/`.failure` like
  every other caller in this codebase does. The control shows `msg_box_error`, nothing is
  marked decided.
- **`repo.decide`/`repo.pending` raising `Sequel::Error`** (DB connection drop mid-session) —
  caught once, centrally, in `ReviewQueueViewModel`'s three action methods and `refresh!`,
  converted to a return value the calling control turns into `msg_box_error`, rather than an
  uncaught exception crashing the LibUI event loop.
- **Timer-driven `refresh!` failing** (e.g. DB briefly unreachable) — logged via `warn`, not
  surfaced as a popup — a background refresh failure shouldn't interrupt whatever the reviewer
  is doing; the next timer tick retries naturally.
- **No pending rows / empty state** — `ItemListControl`'s table just renders empty;
  `DetailPaneControl` shows nothing selected (both modality controls stay invisible, Approve/Reject
  stay disabled via the `enabled <=` binding already described).
- **`source_file` missing/unreadable for an image row** — `image(...)` given a bad path is a
  LibUI-level concern outside this app's control; verify LibUI's actual failure mode for a bad
  image path during implementation (flagged as an implementation-time check, not assumed here).

## Testing

- **`ReviewQueueViewModel`** — the real test surface, entirely display-free: unit tests build it
  with a stub/fake repo (a plain object or RSpec double implementing `#pending`/`#decide`) and a
  stub pipeline (`instance_double(SFL::Core::Pipeline)` returning `Dry::Monads::Success`/`Failure`).
  Covers: `refresh!`'s selection-preservation logic, `approve!`/`reject!` calling `decide` with
  the right decision, `save_and_recompile!`'s compile-then-decide ordering and its failure path
  leaving the row undecided.
- **Custom controls** — not unit tested in the traditional sense (GUI launch needs a display,
  per the `ruby-dev:gui` skill's own testing guidance). `ruby -c` syntax-checks every file. A
  manual smoke-test pass (a documented plan step, not automated) covers: select a row of each
  modality, approve one, reject one, edit-and-recompile one against a real (or
  `Fake::Embedder`/stubbed-provider) LLM config.
- **`exe/sfl-review`** — no automated test; a two-line binstub mirroring `exe/sfl-analyze`'s
  existing (also untested) shape.

## Open Questions for Implementation Planning

- Exact `visible <= [...]` binding syntax for a derived boolean should be re-verified against
  Context7/the `glimmer-dsl-libui` repo examples at implementation time, per the `ruby-dev:gui`
  skill's own "verify each DSL keyword before use" rule — this design's Architecture section
  already flags this as verified-in-spirit (documented pattern by analogy) but not
  verified-by-example.
- Whether `glimmer-dsl-libui` needs adding to the `Gemfile`'s main group or a separate `gui`
  group — it's currently absent entirely; `lib/sfl.rb`'s Zeitwerk loader already
  `ignore`s `lib/sfl/gui` (opt-in require, not eager-loaded), so the require-time wiring only
  needs to happen in `exe/sfl-review`, not `lib/sfl.rb` itself.
- LibUI's actual behavior for `image(bad_path, ...)` (crash vs. blank vs. silently skipped) —
  needs a quick spike before finalizing `ImageReviewControl`'s error handling.
