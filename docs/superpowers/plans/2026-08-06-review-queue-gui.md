# Review Queue GUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `exe/sfl-review`, a Glimmer DSL for LibUI desktop app that lists pending `review_queue` rows (image/text/audio), lets a reviewer approve/reject them, or edit-and-recompile them through the existing `Core::Pipeline`.

**Architecture:** One display-free, unit-tested model (`SFL::GUI::ReviewQueueViewModel`, wrapping `Store::PgReviewQueueRepository` + `Core::Pipeline`) bound via Glimmer's `<=`/`<=>` data-binding to five class-based custom controls (`ItemListControl`, `DetailPaneControl`, `ImageReviewControl`, `TextReviewControl`, and the root `ReviewQueueApp` window). `lib/sfl/gui/` is Zeitwerk-ignored, so every file's own direct dependencies are `require_relative`d explicitly rather than autoloaded.

**Tech Stack:** Ruby 4.0.1, `glimmer-dsl-libui` ~> 0.13 (new dependency), `dry-monads` 1.6 (already a dependency), RSpec.

## Global Constraints

- `frozen_string_literal: true` on every file (project-wide convention).
- `lib/sfl/gui/` is excluded from Zeitwerk autoloading (`lib/sfl.rb`'s `loader.ignore("#{__dir__}/sfl/gui")`) — every file in this plan requires its own direct dependencies via `require_relative` at its own top; nothing relies on autoload for anything under `gui/`.
- `SFL::Boot` stays the only ENV reader for its own concerns (track decision 4). The one exception this plan introduces, per the approved design: `ENV["SFL_REVIEWER_NAME"]` is read once, directly, in `SFL::GUI::ReviewQueueApp` (this mini-app's own composition root) — not threaded through `Boot`, and not read anywhere else.
- Every constructor takes collaborators as injected keyword arguments (`repo:`, `pipeline:`, `viewmodel:`, etc.) — matches this codebase's DI convention everywhere else.
- `rubocop` must pass on every file this plan touches.
- **Resolving the design spec's Finding 5 (left open in the spec as a backlog item):** every `ReviewQueueViewModel` action method (`#refresh!`, `#approve!`, `#reject!`, `#save_and_recompile!`) returns a `Dry::Monads::Result` (`Success`/`Failure`) uniformly — matching `Core::Pipeline#compile`'s own return shape and this codebase's dominant idiom — rather than a bespoke true/false/nil contract. This plan makes that concrete; the spec intentionally left it unspecified.
- **Deferred, not part of this plan** (per the spec's Non-goals and the SIFT review's Findings 2 and 4, both explicitly left as backlog items): a typed `Core::Types::ReviewQueueItem` value object (Finding 2 — this plan uses the raw Sequel Hash rows `PgReviewQueueRepository#pending` already returns), and any concurrent-reviewer locking/guard (Finding 4 — this plan assumes single-reviewer-at-a-time usage).

---

## File Structure

```
Gemfile                                    Task 1 (add glimmer-dsl-libui)
lib/sfl/gui/review_queue_view_model.rb     Task 2 (model, no Glimmer include)
lib/sfl/gui/item_list_control.rb           Task 3
lib/sfl/gui/image_review_control.rb        Task 4
lib/sfl/gui/text_review_control.rb         Task 4
lib/sfl/gui/detail_pane_control.rb         Task 5
lib/sfl/gui/review_queue_app.rb            Task 6
exe/sfl-review                             Task 6
```

Test files:

```
spec/gui/review_queue_view_model_spec.rb   Task 2
```

(Custom controls — Tasks 3-6 — have no automated spec; GUI launch needs a display. Each of those tasks ends in a `ruby -c` syntax check plus a documented manual smoke-test step, per the approved design's own Testing section.)

Every file under `lib/sfl/gui/` requires its own direct dependencies at its top (Global Constraints above) — the exact graph, from the approved design:

```
review_queue_view_model.rb   requires: dry/monads (gem, no local file)
item_list_control.rb         requires: nothing beyond glimmer-dsl-libui itself
image_review_control.rb      requires: nothing beyond glimmer-dsl-libui itself
text_review_control.rb       requires: nothing beyond glimmer-dsl-libui itself
detail_pane_control.rb       requires: image_review_control, text_review_control
review_queue_app.rb          requires: review_queue_view_model, item_list_control, detail_pane_control
exe/sfl-review                requires: glimmer-dsl-libui, ../lib/sfl, ../lib/sfl/gui/review_queue_app
```

---

### Task 1: Add `glimmer-dsl-libui` + verify the three DSL patterns this design depends on

**Files:**
- Modify: `Gemfile` (add gem)
- No production code yet — this task's deliverable is a verified, working understanding of three specific DSL behaviors the rest of the plan assumes.

**Interfaces:**
- Produces: `glimmer-dsl-libui` installed and loadable (`require "glimmer-dsl-libui"` succeeds), and a written confirmation (this task's own commit message) of the three verified behaviors below. No Ruby constants — later tasks import the gem directly.

This resolves two of the approved design's three Open Questions: the gem was entirely absent from the `Gemfile`, and the `visible <= [...]` derived-boolean binding pattern was "verified in spirit, not by example."

- [ ] **Step 1: Add the gem**

In `Gemfile`, after the `tty-prompt` line (the last line before the `group :development, :test do` block), add:

```ruby
# Phase 6 GUI (lib/sfl/gui, exe/sfl-review): first desktop app, wraps
# Store::PgReviewQueueRepository. Bundles libui (the `libui` gem) — no
# Java/Electron dependency, prerequisite-free native windows.
gem "glimmer-dsl-libui", "~> 0.13"
```

- [ ] **Step 2: Install**

Run: `bundle install`
Expected: resolves and installs `glimmer-dsl-libui` (0.13.x) and its `libui` dependency without conflicts; `Gemfile.lock` is updated.

- [ ] **Step 3: Write and run a throwaway verification script**

This script is not committed — it exists only to confirm the three patterns every later task's real code assumes. Save it temporarily as `/tmp/glimmer_spike.rb`:

```ruby
# frozen_string_literal: true

require "glimmer-dsl-libui"

class SpikeModel
  include Glimmer

  attr_accessor :mode, :note

  def initialize
    @mode = "a"
    @note = "hello"
  end
end

class ModeAControl
  include Glimmer::LibUI::CustomControl

  options :model

  body {
    vertical_box {
      visible <= [model, :mode, on_read: ->(m) { m == "a" }]

      label('Mode A is visible')
      multiline_entry { text <=> [model, :note] }
    }
  }
end

class ModeBControl
  include Glimmer::LibUI::CustomControl

  options :model

  body {
    vertical_box {
      visible <= [model, :mode, on_read: ->(m) { m == "b" }]

      label('Mode B is visible')
      area {
        # Point this at any real .png on disk to confirm image() renders;
        # a nonexistent path here confirms the failure mode noted in the
        # design's Error Handling section (observe: does this raise, or
        # render blank?).
        image(File.expand_path("~/.face"), 100, 100) rescue nil
      }
    }
  }
end

class SpikeApp
  include Glimmer

  def launch
    model = SpikeModel.new

    window('Glimmer Spike', 300, 300) {
      margined true

      vertical_box {
        combobox {
          items %w[a b]
          selected_item <=> [model, :mode]
        }

        mode_a_control(model:)
        mode_b_control(model:)
      }
    }.show
  end
end

SpikeApp.new.launch
```

Run: `bundle exec ruby /tmp/glimmer_spike.rb`

Expected (confirm all three before proceeding — these are the exact patterns Tasks 3-6 use verbatim):
1. A window opens with a combobox and, below it, either "Mode A is visible" or "Mode B is visible" depending on the combobox selection — confirms `visible <= [model, :attr, on_read: ->(v) { ... }]` toggles a whole custom control's visibility, resolving the design's Open Question about this exact syntax.
2. Switching the combobox toggles which label shows, live — confirms the binding is reactive, not just evaluated once at construction.
3. Note whether `image(bad_or_missing_path, ...)` inside `area` raised, rendered blank, or silently did nothing — this answers the design's remaining Open Question about `ImageReviewControl`'s error handling. Record the observed behavior in this task's commit message.

- [ ] **Step 4: Delete the spike script**

Run: `rm /tmp/glimmer_spike.rb`

- [ ] **Step 5: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "feat(gui): add glimmer-dsl-libui dependency

Verified via a throwaway spike (not committed): visible <= [model, :attr,
on_read: ...] correctly toggles a class-based custom control's visibility
reactively, and image(<record observed bad-path behavior here>, ...)."
```

(Replace the placeholder in the commit message with what Step 3.3 actually observed — this is the one place this plan asks you to record a live observation rather than assuming one, because it genuinely can't be known without running it.)

---

### Task 2: `SFL::GUI::ReviewQueueViewModel`

**Files:**
- Create: `lib/sfl/gui/review_queue_view_model.rb`
- Test: `spec/gui/review_queue_view_model_spec.rb`

**Interfaces:**
- Consumes: `Store::PgReviewQueueRepository#pending(modality:, limit:, offset:)` → `{items:, total:}`, `#decide(id:, decision:, reviewer:)` → `Hash | nil` (`lib/sfl/store/pg_review_queue_repository.rb`, already implemented, unmodified); `Core::Pipeline#compile(text, document_id:, store:, embed:)` → `Dry::Monads::Result` (`lib/sfl/core/pipeline.rb`, already implemented, unmodified).
- Produces: `SFL::GUI::ReviewQueueViewModel.new(repo:, pipeline:, reviewer_name:, logger: Core::Ports::Null::Logger.new)` with `attr_accessor :items, :selected_item, :modality_filter, :edited_text`, and methods `#refresh! -> Dry::Monads::Result`, `#select(item) -> nil`, `#detail_kind -> Symbol | nil`, `#approve! -> Dry::Monads::Result`, `#reject! -> Dry::Monads::Result`, `#save_and_recompile! -> Dry::Monads::Result`. Consumed by every control in Tasks 3-6.

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/gui/review_queue_view_model_spec.rb
# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/sfl/gui/review_queue_view_model"

RSpec.describe SFL::GUI::ReviewQueueViewModel do
  subject(:view_model) { described_class.new(repo:, pipeline:, reviewer_name: "bob") }

  let(:repo) { instance_double(SFL::Store::PgReviewQueueRepository) }
  let(:pipeline) { instance_double(SFL::Core::Pipeline) }

  let(:pending_row) do
    { id: "row-1", document_id: "doc-1", modality: "text", reason: "low_quality_score",
      source_file: "notes.md", generated_text: "Some flagged text.", created_at: Time.now }
  end

  describe "#refresh!" do
    it "populates items from repo.pending, scoped by modality_filter" do
      allow(repo).to receive(:pending).with(modality: nil).and_return(items: [pending_row], total: 1)

      result = view_model.refresh!

      expect(result).to be_success
      expect(view_model.items).to eq([pending_row])
    end

    it "passes modality_filter through when it isn't \"all\"" do
      view_model.modality_filter = "image"
      allow(repo).to receive(:pending).with(modality: "image").and_return(items: [], total: 0)

      view_model.refresh!

      expect(repo).to have_received(:pending).with(modality: "image")
    end

    it "keeps the current selection when it's still present in the refreshed items" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)

      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.refresh!

      expect(view_model.selected_item).to eq(pending_row)
    end

    it "preserves edited_text across a refresh that keeps the selection" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)
      view_model.edited_text = "a reviewer's in-progress correction"

      view_model.refresh!

      expect(view_model.edited_text).to eq("a reviewer's in-progress correction")
    end

    it "clears the selection when the previously-selected row is no longer pending" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)

      allow(repo).to receive(:pending).and_return(items: [], total: 0)
      view_model.refresh!

      expect(view_model.selected_item).to be_nil
      expect(view_model.edited_text).to be_nil
    end

    it "returns Failure without raising when the repo raises Sequel::Error" do
      allow(repo).to receive(:pending).and_raise(Sequel::Error, "connection lost")

      result = view_model.refresh!

      expect(result).to be_failure
    end
  end

  describe "#select" do
    it "sets selected_item and seeds edited_text from generated_text" do
      view_model.select(pending_row)

      expect(view_model.selected_item).to eq(pending_row)
      expect(view_model.edited_text).to eq("Some flagged text.")
    end
  end

  describe "#detail_kind" do
    it "is nil when nothing is selected" do
      expect(view_model.detail_kind).to be_nil
    end

    it "is :image for modality image" do
      view_model.select(pending_row.merge(modality: "image"))
      expect(view_model.detail_kind).to eq(:image)
    end

    it "is :text for modality text or audio" do
      view_model.select(pending_row.merge(modality: "text"))
      expect(view_model.detail_kind).to eq(:text)

      view_model.select(pending_row.merge(modality: "audio"))
      expect(view_model.detail_kind).to eq(:text)
    end

    it "is :unrecognized for any other modality value" do
      view_model.select(pending_row.merge(modality: "video"))
      expect(view_model.detail_kind).to eq(:unrecognized)
    end
  end

  describe "#approve!" do
    it "calls repo.decide with decision approve and the reviewer name, then refreshes" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)
      allow(repo).to receive(:decide).and_return(pending_row.merge(status: "approved"))
      allow(repo).to receive(:pending).and_return(items: [], total: 0)

      result = view_model.approve!

      expect(repo).to have_received(:decide).with(id: "row-1", decision: "approve", reviewer: "bob")
      expect(result).to be_success
    end

    it "returns Failure without calling decide when nothing is selected" do
      result = view_model.approve!

      expect(repo).not_to have_received(:decide)
      expect(result).to be_failure
    end
  end

  describe "#reject!" do
    it "calls repo.decide with decision reject" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)
      allow(repo).to receive(:decide).and_return(pending_row.merge(status: "rejected"))
      allow(repo).to receive(:pending).and_return(items: [], total: 0)

      view_model.reject!

      expect(repo).to have_received(:decide).with(id: "row-1", decision: "reject", reviewer: "bob")
    end
  end

  describe "#save_and_recompile!" do
    it "calls pipeline.compile first, and only calls decide(edit) on Success" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)
      view_model.edited_text = "corrected text"
      compile_success = Dry::Monads::Success([:some_annotated_clause])
      allow(pipeline).to receive(:compile)
        .with("corrected text", document_id: "doc-1", store: true, embed: true)
        .and_return(compile_success)
      allow(repo).to receive(:decide).and_return(pending_row.merge(status: "edited"))
      allow(repo).to receive(:pending).and_return(items: [], total: 0)

      result = view_model.save_and_recompile!

      expect(pipeline).to have_received(:compile).with("corrected text", document_id: "doc-1", store: true, embed: true)
      expect(repo).to have_received(:decide).with(id: "row-1", decision: "edit", reviewer: "bob")
      expect(result).to be_success
    end

    it "does not call decide, and returns the Failure, when pipeline.compile fails" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)
      view_model.edited_text = "corrected text"
      compile_failure = Dry::Monads::Failure([:pass_one_failed, "sidecar crashed"])
      allow(pipeline).to receive(:compile).and_return(compile_failure)
      allow(repo).to receive(:decide)

      result = view_model.save_and_recompile!

      expect(repo).not_to have_received(:decide)
      expect(result).to eq(compile_failure)
    end

    it "preserves edited_text after a failed recompile" do
      allow(repo).to receive(:pending).and_return(items: [pending_row], total: 1)
      view_model.select(pending_row)
      view_model.edited_text = "corrected text"
      allow(pipeline).to receive(:compile).and_return(Dry::Monads::Failure([:pass_one_failed, "boom"]))

      view_model.save_and_recompile!

      expect(view_model.edited_text).to eq("corrected text")
    end

    it "returns Failure without calling pipeline.compile when nothing is selected" do
      result = view_model.save_and_recompile!

      expect(pipeline).not_to have_received(:compile)
      expect(result).to be_failure
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/gui/review_queue_view_model_spec.rb`
Expected: FAIL with `uninitialized constant SFL::GUI::ReviewQueueViewModel`

- [ ] **Step 3: Write the implementation**

```ruby
# lib/sfl/gui/review_queue_view_model.rb
# frozen_string_literal: true

require "dry/monads"

module SFL
  module GUI
    # Model layer for the review queue GUI (lib/sfl/gui/review_queue_app.rb) —
    # the only class in this app that touches Store::PgReviewQueueRepository/
    # Core::Pipeline directly. Every custom control reads/writes this via
    # Glimmer data-binding, never the repo/pipeline themselves.
    #
    # No Glimmer include here on purpose: this class has no view concerns,
    # which is what makes it unit-testable without a display (see
    # spec/gui/review_queue_view_model_spec.rb).
    #
    # Every action method returns a Dry::Monads::Result, matching
    # Core::Pipeline#compile's own return shape — a deliberate, concrete
    # resolution of the design spec's Finding 5 (left open there as "a
    # return value the calling control turns into a dialog," unspecified
    # shape).
    class ReviewQueueViewModel
      include Dry::Monads[:result]

      attr_accessor :items, :selected_item, :modality_filter, :edited_text

      # @param repo [Store::PgReviewQueueRepository]
      # @param pipeline [Core::Pipeline]
      # @param reviewer_name [String] read from ENV by the caller (SFL::GUI::ReviewQueueApp),
      #   not by this class — see this plan's Global Constraints.
      # @param logger [#debug,#info,#warn,#error] Core::Ports::Logger-compatible
      def initialize(repo:, pipeline:, reviewer_name:, logger: Core::Ports::Null::Logger.new)
        @repo = repo
        @pipeline = pipeline
        @reviewer_name = reviewer_name
        @logger = logger
        @items = []
        @selected_item = nil
        @modality_filter = "all"
        @edited_text = nil
      end

      # @return [Dry::Monads::Result] Success(items) or Failure(message)
      def refresh!
        self.items = repo.pending(modality: modality_filter_param).fetch(:items)
        sync_selection_after_refresh
        Success(items)
      rescue Sequel::Error => e
        logger.warn { "review queue refresh failed: #{e.message}" }
        Failure(e.message)
      end

      # @param item [Hash] a row from #items
      def select(item)
        self.selected_item = item
        self.edited_text = item[:generated_text]
      end

      # @return [Symbol, nil] :image | :text | :unrecognized | nil (nothing selected)
      def detail_kind
        return nil if selected_item.nil?

        case selected_item[:modality]
        when "image" then :image
        when "text", "audio" then :text
        else :unrecognized
        end
      end

      # @return [Dry::Monads::Result]
      def approve!
        decide!("approve")
      end

      # @return [Dry::Monads::Result]
      def reject!
        decide!("reject")
      end

      # @return [Dry::Monads::Result]
      def save_and_recompile!
        return Failure("no item selected") unless selected_item

        compile_result = pipeline.compile(edited_text, document_id: selected_item[:document_id], store: true, embed: true)
        return compile_result if compile_result.failure?

        decide!("edit")
      end

      attr_reader :repo, :pipeline, :reviewer_name, :logger
      private :repo, :pipeline, :reviewer_name, :logger

      private def decide!(decision)
        return Failure("no item selected") unless selected_item

        repo.decide(id: selected_item[:id], decision:, reviewer: reviewer_name)
        refresh!
      rescue Sequel::Error => e
        logger.warn { "review queue #{decision} failed: #{e.message}" }
        Failure(e.message)
      end

      private def modality_filter_param
        modality_filter == "all" ? nil : modality_filter
      end

      # Preserves selection/edited_text across a refresh IF the selected row is still
      # pending; clears both if it disappeared (resolved by this app or another process).
      private def sync_selection_after_refresh
        return unless selected_item

        still_present = items.find { |item| item[:id] == selected_item[:id] }
        self.selected_item = still_present
        self.edited_text = nil unless still_present
      end
    end
  end
end
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/gui/review_queue_view_model_spec.rb`
Expected: PASS (17 examples)

- [ ] **Step 5: Rubocop**

Run: `bundle exec rubocop lib/sfl/gui/review_queue_view_model.rb spec/gui/review_queue_view_model_spec.rb`
Expected: no offenses

- [ ] **Step 6: Commit**

```bash
git add lib/sfl/gui/review_queue_view_model.rb spec/gui/review_queue_view_model_spec.rb
git commit -m "feat(gui): add ReviewQueueViewModel"
```

---

### Task 3: `SFL::GUI::ItemListControl`

**Files:**
- Create: `lib/sfl/gui/item_list_control.rb`

**Interfaces:**
- Consumes: `ReviewQueueViewModel#items`/`#modality_filter`/`#select`/`#refresh!` (Task 2).
- Produces: `item_list_control(viewmodel:)` DSL keyword, one root `vertical_box` containing a modality-filter `combobox` and a `table`. Consumed by Task 6 (`ReviewQueueApp`).

- [ ] **Step 1: Write the implementation**

No automated spec (custom controls need a display — see this plan's File Structure note). `ruby -c` in Step 2 is this task's correctness gate; a manual smoke test happens once the whole app exists in Task 6.

```ruby
# lib/sfl/gui/item_list_control.rb
# frozen_string_literal: true

module SFL
  module GUI
    # Left pane: a modality filter and the table of pending review_queue rows.
    # Selecting a row calls viewmodel.select — every other control reacts to
    # that via data-binding, this control never talks to them directly.
    class ItemListControl
      include Glimmer::LibUI::CustomControl

      options :viewmodel

      body {
        vertical_box {
          combobox {
            items %w[all image text audio]
            selected_item <=> [viewmodel, :modality_filter]

            on_selected { viewmodel.refresh! }
          }

          table {
            text_column('Modality')
            text_column('Reason')
            text_column('Source File')
            text_column('Created At')

            cell_rows <= [viewmodel, :items, on_read: ->(items) {
              items.map { |item| [item[:modality], item[:reason], item[:source_file], item[:created_at].to_s] }
            }]

            on_row_clicked { |row| viewmodel.select(viewmodel.items[row]) }
          }
        }
      }
    end
  end
end
```

- [ ] **Step 2: Syntax check**

Run: `ruby -c lib/sfl/gui/item_list_control.rb`
Expected: `Syntax OK`

- [ ] **Step 3: Rubocop**

Run: `bundle exec rubocop lib/sfl/gui/item_list_control.rb`
Expected: no offenses

- [ ] **Step 4: Commit**

```bash
git add lib/sfl/gui/item_list_control.rb
git commit -m "feat(gui): add ItemListControl"
```

---

### Task 4: `SFL::GUI::ImageReviewControl` + `SFL::GUI::TextReviewControl`

**Files:**
- Create: `lib/sfl/gui/image_review_control.rb`
- Create: `lib/sfl/gui/text_review_control.rb`

**Interfaces:**
- Consumes: `ReviewQueueViewModel#detail_kind`/`#selected_item`/`#edited_text`/`#save_and_recompile!` (Task 2).
- Produces: `image_review_control(viewmodel:)` and `text_review_control(viewmodel:)` DSL keywords. Both consumed by Task 5 (`DetailPaneControl`).

- [ ] **Step 1: Write `ImageReviewControl`**

```ruby
# lib/sfl/gui/image_review_control.rb
# frozen_string_literal: true

module SFL
  module GUI
    # Renders the flagged image inline plus its editable generated
    # description, for a selected review_queue row whose modality is
    # "image". Always present in DetailPaneControl's tree; visible is
    # bound to viewmodel.detail_kind so it's provably the complement of
    # TextReviewControl's own visible binding (SIFT Finding 1 fix — see
    # ReviewQueueViewModel#detail_kind, the single source of truth both
    # controls read from).
    class ImageReviewControl
      include Glimmer::LibUI::CustomControl

      options :viewmodel

      body {
        vertical_box {
          visible <= [viewmodel, :detail_kind, on_read: ->(kind) { kind == :image }]

          area {
            image(viewmodel.selected_item&.dig(:source_file), 400, 400)
          }

          multiline_entry {
            text <=> [viewmodel, :edited_text]
          }

          button('Save & Recompile') {
            on_clicked do
              result = viewmodel.save_and_recompile!
              msg_box_error('Recompile failed', result.failure.inspect) if result.failure?
            end
          }
        }
      }
    end
  end
end
```

- [ ] **Step 2: Write `TextReviewControl`**

```ruby
# lib/sfl/gui/text_review_control.rb
# frozen_string_literal: true

module SFL
  module GUI
    # Same shape as ImageReviewControl minus the image — serves both
    # "text" and "audio" modalities identically (audio has no special
    # rendering need beyond its transcript text). visible is bound to
    # viewmodel.detail_kind, the same single source of truth
    # ImageReviewControl reads (SIFT Finding 1 fix).
    class TextReviewControl
      include Glimmer::LibUI::CustomControl

      options :viewmodel

      body {
        vertical_box {
          visible <= [viewmodel, :detail_kind, on_read: ->(kind) { kind == :text }]

          multiline_entry {
            text <=> [viewmodel, :edited_text]
          }

          button('Save & Recompile') {
            on_clicked do
              result = viewmodel.save_and_recompile!
              msg_box_error('Recompile failed', result.failure.inspect) if result.failure?
            end
          }
        }
      }
    end
  end
end
```

- [ ] **Step 3: Syntax check both**

Run: `ruby -c lib/sfl/gui/image_review_control.rb lib/sfl/gui/text_review_control.rb`
Expected: `Syntax OK` for both

- [ ] **Step 4: Rubocop**

Run: `bundle exec rubocop lib/sfl/gui/image_review_control.rb lib/sfl/gui/text_review_control.rb`
Expected: no offenses

- [ ] **Step 5: Commit**

```bash
git add lib/sfl/gui/image_review_control.rb lib/sfl/gui/text_review_control.rb
git commit -m "feat(gui): add ImageReviewControl and TextReviewControl"
```

---

### Task 5: `SFL::GUI::DetailPaneControl`

**Files:**
- Create: `lib/sfl/gui/detail_pane_control.rb`

**Interfaces:**
- Consumes: `image_review_control`/`text_review_control` DSL keywords (Task 4), `ReviewQueueViewModel#selected_item`/`#detail_kind`/`#approve!`/`#reject!` (Task 2).
- Produces: `detail_pane_control(viewmodel:)` DSL keyword. Consumed by Task 6 (`ReviewQueueApp`).

- [ ] **Step 1: Write the implementation**

```ruby
# lib/sfl/gui/detail_pane_control.rb
# frozen_string_literal: true

require_relative "image_review_control"
require_relative "text_review_control"

module SFL
  module GUI
    # Right pane: selected-row metadata, the modality-specific review
    # control (exactly one of ImageReviewControl/TextReviewControl is
    # visible at a time, or neither if nothing recognized is selected —
    # see the fallback label below), and the shared Approve/Reject
    # buttons, which are modality-agnostic so they live here once rather
    # than being duplicated in every modality control.
    class DetailPaneControl
      include Glimmer::LibUI::CustomControl

      options :viewmodel

      body {
        vertical_box {
          label {
            text <= [viewmodel, :selected_item, on_read: ->(item) { item ? "Modality: #{item[:modality]}" : "" }]
          }
          label {
            text <= [viewmodel, :selected_item, on_read: ->(item) { item ? "Reason: #{item[:reason]}" : "" }]
          }
          label {
            text <= [viewmodel, :selected_item, on_read: ->(item) { item ? "Source: #{item[:source_file]}" : "" }]
          }
          label {
            text <= [viewmodel, :selected_item, on_read: ->(item) { item ? "Created: #{item[:created_at]}" : "" }]
          }

          image_review_control(viewmodel:)
          text_review_control(viewmodel:)

          # Exhaustiveness fallback (SIFT Finding 1): an unrecognized modality
          # shows an explicit message instead of a silent blank pane — the
          # complement of both review controls' visible bindings, all three
          # reading the same viewmodel.detail_kind single source of truth.
          label {
            text <= [viewmodel, :detail_kind, on_read: ->(kind) {
              kind == :unrecognized ? "No reviewer UI for modality #{viewmodel.selected_item[:modality].inspect} yet." : ""
            }]
          }

          button('Approve') {
            enabled <= [viewmodel, :selected_item, on_read: ->(item) { !item.nil? }]

            on_clicked do
              result = viewmodel.approve!
              msg_box_error('Approve failed', result.failure.inspect) if result.failure?
            end
          }

          button('Reject') {
            enabled <= [viewmodel, :selected_item, on_read: ->(item) { !item.nil? }]

            on_clicked do
              result = viewmodel.reject!
              msg_box_error('Reject failed', result.failure.inspect) if result.failure?
            end
          }
        }
      }
    end
  end
end
```

- [ ] **Step 2: Syntax check**

Run: `ruby -c lib/sfl/gui/detail_pane_control.rb`
Expected: `Syntax OK`

- [ ] **Step 3: Rubocop**

Run: `bundle exec rubocop lib/sfl/gui/detail_pane_control.rb`
Expected: no offenses

- [ ] **Step 4: Commit**

```bash
git add lib/sfl/gui/detail_pane_control.rb
git commit -m "feat(gui): add DetailPaneControl"
```

---

### Task 6: `SFL::GUI::ReviewQueueApp` + `exe/sfl-review`

**Files:**
- Create: `lib/sfl/gui/review_queue_app.rb`
- Create: `exe/sfl-review`

**Interfaces:**
- Consumes: `item_list_control`/`detail_pane_control` DSL keywords (Tasks 3, 5), `ReviewQueueViewModel.new` (Task 2), `SFL::Boot.call`, `SFL::CLI.build_pipeline` (`lib/sfl/cli.rb:409-428`, reused unmodified), `Store::PgReviewQueueRepository.new` (unmodified).
- Produces: `SFL::GUI::ReviewQueueApp.new.launch`, and the `exe/sfl-review` binstub that calls it. This is the plan's final task — end-to-end manual smoke test closes it out.

**Implementation note:** uses the `include Glimmer` + plain instance `#launch` method pattern (the `ruby-dev:gui` skill's own golden-structure example, `TaskManager.new.launch`) rather than the `Glimmer::LibUI::CustomWindow` class-macro form (`before_body`/`body`/`after_body`). The skill's reference docs confirm `CustomWindow` exists but don't show state set in `before_body` being read inside `body` the way this app needs (build the ViewModel once, then reference it from both the window layout and the timer) — the golden-structure pattern is the one this plan has full, directly-documented confidence in, so it's used for the one file where getting this wrong means the whole app doesn't launch.

- [ ] **Step 1: Write `ReviewQueueApp`**

```ruby
# lib/sfl/gui/review_queue_app.rb
# frozen_string_literal: true

require_relative "review_queue_view_model"
require_relative "item_list_control"
require_relative "detail_pane_control"

module SFL
  module GUI
    # Composition root for the review queue GUI: boots the app's real
    # collaborators (DB, LLM, pipeline) exactly once, builds the
    # ReviewQueueViewModel, and lays out ItemListControl/DetailPaneControl
    # side by side. Owns the auto-refresh timer.
    class ReviewQueueApp
      include Glimmer

      REFRESH_INTERVAL_SECONDS = 10

      attr_reader :viewmodel

      def initialize
        # require_tracing: false unconditionally — LangfuseReachability's
        # reachability prompt expects an interactive tty, which this GUI
        # process doesn't have in the CLI's sense (see the design doc).
        boot_result = Boot.call(require_llm: true, require_tracing: false)
        logger = Core::Ports::StandardLogger.new(progname: "sfl.gui")
        pipeline = CLI.build_pipeline(
          boot_result, { pass1_only: false, store: true, resume: false },
          breaker: Core::Ports::Null::Breaker.new, instrumenter: Core::Ports::Null::Instrumenter.new, logger:
        )
        repo = Store::PgReviewQueueRepository.new(boot_result.db)
        reviewer_name = ENV["SFL_REVIEWER_NAME"]

        @viewmodel = ReviewQueueViewModel.new(repo:, pipeline:, reviewer_name:, logger:)
        @viewmodel.refresh!
      end

      def launch
        Glimmer::LibUI.timer(REFRESH_INTERVAL_SECONDS) { viewmodel.refresh! }

        window('SFL Review Queue', 900, 500) {
          margined true

          horizontal_box {
            item_list_control(viewmodel:)
            detail_pane_control(viewmodel:)
          }
        }.show
      end
    end
  end
end
```

- [ ] **Step 2: Write `exe/sfl-review`**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Running from a repo checkout (no gemspec — track decision 1), same as
# exe/sfl-analyze — bundler doesn't add this app's lib/ to the load path
# on its own.
lib = File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift(lib) if File.directory?(lib) && !$LOAD_PATH.include?(lib)

require "glimmer-dsl-libui"
require_relative "../lib/sfl"
require_relative "../lib/sfl/gui/review_queue_app"

SFL::DockerServices.ensure_running!

SFL::GUI::ReviewQueueApp.new.launch
```

- [ ] **Step 3: Make it executable**

Run: `chmod +x exe/sfl-review`

- [ ] **Step 4: Syntax check both files**

Run: `ruby -c lib/sfl/gui/review_queue_app.rb exe/sfl-review`
Expected: `Syntax OK` for both

- [ ] **Step 5: Rubocop**

Run: `bundle exec rubocop lib/sfl/gui/review_queue_app.rb exe/sfl-review`
Expected: no offenses

- [ ] **Step 6: Manual end-to-end smoke test**

Prerequisite: at least one row in `review_queue` with `status = 'pending'`. If none exist, insert one directly for this test:

```sql
INSERT INTO review_queue (id, modality, document_id, source_file, generated_text, reason, status, created_at)
VALUES ('smoke-test-1', 'text', 'smoke-doc-1', 'smoke.md', 'This is flagged text for a smoke test.', 'low_quality_score', 'pending', now());
```

Run: `bundle exec exe/sfl-review`

Expected, walking the design doc's own worked examples:
1. Window opens, showing the smoke-test row in the left table.
2. Clicking the row shows its metadata and the text-review control (not the image control) in the right pane, `edited_text` pre-filled with "This is flagged text for a smoke test."
3. Click **Approve** — the row disappears from the table (status flipped to `approved`; confirm via `psql` if desired: `SELECT status FROM review_queue WHERE id = 'smoke-test-1'`).
4. Insert a second pending row, edit its text in the multiline entry, click **Save & Recompile** — confirm no `msg_box_error` appears (or, if Pass 2/DB isn't fully configured in this environment, confirm the error dialog appears with a legible message rather than a crash) and, on success, the row disappears from the table.
5. Wait 10+ seconds with nothing selected — confirm the app doesn't freeze or error (the timer's `refresh!` call succeeding silently in the background).

- [ ] **Step 7: Commit**

```bash
git add lib/sfl/gui/review_queue_app.rb exe/sfl-review
git commit -m "feat(gui): add ReviewQueueApp and exe/sfl-review binstub"
```

---

## Self-Review

**Spec coverage** — every Goal in the approved design has a task: list+inspect (Tasks 3, 5), Approve/Reject (Task 2's `#approve!`/`#reject!`, wired in Task 5), Edit-and-recompile (Task 2's `#save_and_recompile!`, wired in Task 4), auto-refresh without clobbering selection (Task 2's `#refresh!`/`sync_selection_after_refresh`, wired in Task 6). Both SIFT-driven spec fixes (Finding 1's `#detail_kind` exhaustiveness, Finding 3's require graph) are implemented exactly as the revised spec states, in Tasks 2 and 3-6 respectively. The spec's three Open Questions are all resolved in Task 1 (gem added, `visible <=` pattern verified, image-bad-path behavior to be recorded from the live spike) rather than carried forward as unknowns.

**Placeholder scan** — no TBD/TODO/"add error handling"-style steps; every step has literal, complete code. The one deliberately-left variable is Task 1 Step 5's commit-message placeholder for the spike's observed image-bad-path behavior — flagged inline as something that must be filled from a live run, not guessable in advance, consistent with the "No Placeholders" rule's spirit (this is a recorded observation, not a description of what to do).

**Type/signature consistency** — `ReviewQueueViewModel#detail_kind`'s three-way return (`:image | :text | :unrecognized`, Task 2) is read identically by `ImageReviewControl`/`TextReviewControl`'s `visible` bindings (Task 4) and `DetailPaneControl`'s fallback label (Task 5) — no control recomputes its own predicate, resolving SIFT Finding 1 as designed. Every `ReviewQueueViewModel` action method's `Dry::Monads::Result` return (Task 2) is consumed identically by every button handler (`result.failure?` / `result.failure.inspect`, Tasks 4-5) — one uniform contract, resolving Finding 5. `CLI.build_pipeline`'s existing three-key options Hash (`pass1_only:`, `store:`, `resume:`) is passed with all three keys in Task 6, matching its real signature (`lib/sfl/cli.rb:409`) rather than a subset.
