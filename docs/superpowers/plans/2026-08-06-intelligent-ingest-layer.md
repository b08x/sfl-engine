# Intelligent Ingest Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one CLI entry point (`sfl-analyze ingest <path>`) that classifies a file or directory of mixed input formats (deterministic rules first, LLM fallback second) and dispatches each file to the correct existing analysis engine, drafting a candidate loader for genuinely unrecognized formats and persisting low-confidence/drafted cases to a reviewable Postgres table.

**Architecture:** A new `SFL::Ingest` namespace (`DeterministicRules`, `LoaderDrafter`, `Orchestrator`) sits above the three existing, unmodified analysis entry points (`Analysis::Engine` for conversation/documentation, `Analysis::KnowledgeBaseSource` for KB). A new `Core::Ports::Classifier` port (with `Null`/`Fake`/`LLM` adapters, mirroring every other port in this codebase) and a new `ingest_review_entries` Postgres table (mirroring `review_queue`'s exact shape) round out the new surface. Two new per-task model configs (`ingest_classification`, `loader_drafting`) are added to `SFL::Boot` alongside the four that already exist.

**Tech Stack:** Ruby 4.0.1, Sequel 5.88 (Postgres), Dry::Struct 1.8, ruby_llm 1.16 + ruby_llm-schema 0.4, RSpec.

## Global Constraints

- Ruby 4.0.1, `frozen_string_literal: true` on every file (project-wide convention, verified across every file read in this codebase).
- Zeitwerk autoloading (`lib/sfl.rb`) — no manual `require` needed for new `SFL::*` classes; one class/module per file, filename is the `snake_case` of the constant name, directory path mirrors the namespace. No new Zeitwerk inflection entries are needed for anything in this plan (`Ingest`, `Classifier`, `LoaderDrafter`, `Orchestrator`, `DeterministicRules` all camelize correctly by default).
- Every constructor takes its collaborators as **injected keyword arguments** with `Null::*`/production defaults where established elsewhere in this codebase (see `LLM::Engine#initialize`, `Core::Pipeline#initialize`) — never reads `ENV` directly outside `SFL::Boot` (track decision 4, `lib/sfl/boot.rb:7-13`).
- Every new port gets `Null::*` and, where a spec needs controllable output, `Fake::*` adapters (see `Core::Ports::Embedder`/`Null::Embedder`/`Fake::Embedder`).
- Migrations are plain `Sequel.migration do change do ... end end` blocks, next sequential number after the existing `008_add_embedding_status_to_clauses.rb`, run only via `rake db:migrate` — never auto-run at boot (track decision 5, `lib/sfl/boot.rb:21-23`).
- `rubocop` must pass on every file this plan touches (`bundle exec rubocop <path>`); this codebase's `Gemfile` pins `rubocop-shopify`/`rubocop-rspec`/`rubocop-sequel` — follow the double-quote-strings, `module_function def`, and per-port doc-comment conventions visible in every file read during planning.
- **Explicitly deferred, not part of this plan** (per the spec's Non-goals and Open Questions): any UI, and any `ingest review`/`ingest resolve <id>` CLI subcommand for acting on `ingest_review_entries` rows. This plan only inserts rows; reading/resolving them by hand (`psql`, or a future CLI/UI) is out of scope.

---

## File Structure

New files, grouped by responsibility:

```
db/migrations/009_create_ingest_review_entries.rb   Task 1
lib/sfl/store/pg_ingest_review_repository.rb         Task 2
lib/sfl/core/types/classification_result.rb          Task 3
lib/sfl/core/ports/classifier.rb                     Task 4
lib/sfl/core/ports/null/classifier.rb                Task 4
lib/sfl/core/ports/fake/classifier.rb                Task 4
lib/sfl/ingest/deterministic_rules.rb                 Task 5
lib/sfl/llm/schemas/classification_schema.rb          Task 6
lib/sfl/prompts/templates/ingest_classification.txt.erb  Task 6
lib/sfl/llm/classifier.rb                             Task 6
lib/sfl/llm/schemas/loader_draft_schema.rb            Task 8
lib/sfl/prompts/templates/loader_drafting.txt.erb     Task 8
lib/sfl/ingest/loader_drafter.rb                      Task 8
lib/sfl/ingest/orchestrator.rb                        Task 9
```

Modified files:

```
spec/support/store_test_db.rb   Task 1 (TRUNCATE list)
lib/sfl/boot.rb                 Task 7 (TASK_NAMES + two new task configs + build_classifier)
lib/sfl/cli.rb                  Task 10 (ingest subcommand)
```

Each `.rb` file above has exactly one class/module. `Ingest::Orchestrator` is the only file that depends on the other `Ingest::*`/`Core::Ports::Classifier`/`Store::PgIngestReviewRepository` files together — every other file is independently testable against fakes/doubles, matching this codebase's existing port-per-file granularity.

---

### Task 1: `ingest_review_entries` migration + test-db wiring

**Files:**
- Create: `db/migrations/009_create_ingest_review_entries.rb`
- Modify: `spec/support/store_test_db.rb:49-53` (add `ingest_review_entries` to the `TRUNCATE` list)
- Test: implicit — `spec/support/store_test_db.rb`'s `StoreTestDb.db` runs every migration in `db/migrations` via `Sequel::Migrator.run`, so Task 2's repository spec is this migration's real test.

**Interfaces:**
- Produces: a `:ingest_review_entries` Postgres table with columns `id, path, status, format, mode, confidence, reasoning, loader_path, doc_path, created_at, resolved_at`, `status` defaulting to `"pending"`, indexed on `status`.

- [ ] **Step 1: Write the migration**

```ruby
# db/migrations/009_create_ingest_review_entries.rb
# frozen_string_literal: true

# Ingest-time review queue: rows written when Ingest::Orchestrator can't
# confidently dispatch a file on its own (see Ingest::DeterministicRules /
# Core::Ports::Classifier / Ingest::LoaderDrafter). Mirrors review_queue's
# exact shape (db/migrations/007_create_review_queue.rb) — String UUID
# primary key, status defaults to "pending", indexed on status — so a
# future UI or CLI review subcommand is a pure read/query layer on this
# table, not a migration to write later.
Sequel.migration do
  change do
    create_table(:ingest_review_entries) do
      String :id, primary_key: true # UUID
      String :path, null: false, text: true
      # low_confidence_mode | loader_drafted | draft_failed | resolved
      String :status, null: false, default: "pending"
      String :format
      String :mode
      Float :confidence
      String :reasoning, text: true, null: false
      String :loader_path
      String :doc_path
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :resolved_at

      index :status, name: :idx_ingest_review_entries_status
    end
  end
end
```

- [ ] **Step 2: Add the table to `StoreTestDb.clean!`'s TRUNCATE list**

Read `spec/support/store_test_db.rb` first (Edit requires a prior Read). Change:

```ruby
      def self.clean!
        db.run(<<~SQL)
          TRUNCATE clauses, ideational_payloads, interpersonal_payloads, embeddings,
                   annotation_reviews, review_queue
          RESTART IDENTITY CASCADE
        SQL
      end
```

to:

```ruby
      def self.clean!
        db.run(<<~SQL)
          TRUNCATE clauses, ideational_payloads, interpersonal_payloads, embeddings,
                   annotation_reviews, review_queue, ingest_review_entries
          RESTART IDENTITY CASCADE
        SQL
      end
```

- [ ] **Step 3: Run migrations against the test database**

Run: `bundle exec rake db:migrate`
Expected: no errors; `psql "$DATABASE_URL_V2_TEST" -c '\d ingest_review_entries'` (or the dev DB if `DATABASE_URL_V2_TEST` isn't set) shows the new table.

- [ ] **Step 4: Commit**

```bash
git add db/migrations/009_create_ingest_review_entries.rb spec/support/store_test_db.rb
git commit -m "feat(store): add ingest_review_entries table"
```

---

### Task 2: `Store::PgIngestReviewRepository`

**Files:**
- Create: `lib/sfl/store/pg_ingest_review_repository.rb`
- Test: `spec/store/pg_ingest_review_repository_spec.rb`

**Interfaces:**
- Consumes: `Sequel::Database` (`db:`), the `ingest_review_entries` table from Task 1.
- Produces: `Store::PgIngestReviewRepository.new(db)`, with `#enqueue(path:, status:, reasoning:, format: nil, mode: nil, confidence: nil, loader_path: nil, doc_path: nil) -> String` (new row's id), `#find(id) -> Hash | nil`, `#resolved?(path) -> Boolean` (used by `Ingest::Orchestrator` in Task 9 to skip already-resolved paths on rerun).

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/store/pg_ingest_review_repository_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Store::PgIngestReviewRepository do
  subject(:repo) { described_class.new(db) }

  let(:db) { SFL::Store::StoreTestDb.db }

  before { SFL::Store::StoreTestDb.clean! }

  describe "#enqueue" do
    it "inserts a pending row and returns its id" do
      id = repo.enqueue(
        path: "export-dump/weird_chat.jsonl", status: "loader_drafted",
        format: "unknown", mode: nil, confidence: 0.2,
        reasoning: "JSONL rows resembling a chat log, but no loader recognizes this shape",
        loader_path: "lib/sfl/core/loaders/generic_jsonl_chat_source.rb",
        doc_path: "docs/ingest-review/generic_jsonl_chat_source.md"
      )

      row = db[:ingest_review_entries].where(id:).first
      expect(row).to include(
        path: "export-dump/weird_chat.jsonl", status: "loader_drafted",
        format: "unknown", confidence: 0.2,
        loader_path: "lib/sfl/core/loaders/generic_jsonl_chat_source.rb"
      )
      expect(row[:mode]).to be_nil
      expect(row[:resolved_at]).to be_nil
    end

    it "defaults status to pending when not given" do
      id = repo.enqueue(path: "a.md", reasoning: "ambiguous mode")

      expect(db[:ingest_review_entries].where(id:).first[:status]).to eq("pending")
    end
  end

  describe "#find" do
    it "returns the row for a known id" do
      id = repo.enqueue(path: "a.md", status: "low_confidence_mode", reasoning: "ambiguous")

      expect(repo.find(id)[:path]).to eq("a.md")
    end

    it "returns nil for an unknown id" do
      expect(repo.find("missing")).to be_nil
    end
  end

  describe "#resolved?" do
    it "is false for a path with no review entry at all" do
      expect(repo.resolved?("never-seen.md")).to be(false)
    end

    it "is false for a path with only an unresolved entry" do
      repo.enqueue(path: "a.md", status: "low_confidence_mode", reasoning: "ambiguous")

      expect(repo.resolved?("a.md")).to be(false)
    end

    it "is true once that path's row has status resolved" do
      id = repo.enqueue(path: "a.md", status: "low_confidence_mode", reasoning: "ambiguous")
      db[:ingest_review_entries].where(id:).update(status: "resolved", resolved_at: Time.now)

      expect(repo.resolved?("a.md")).to be(true)
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/store/pg_ingest_review_repository_spec.rb`
Expected: FAIL with `uninitialized constant SFL::Store::PgIngestReviewRepository`

- [ ] **Step 3: Write the implementation**

```ruby
# lib/sfl/store/pg_ingest_review_repository.rb
# frozen_string_literal: true

require "sequel"
require "securerandom"

module SFL
  module Store
    # Postgres-backed review queue for Ingest::Orchestrator — rows written
    # when a file can't be confidently classified/dispatched on its own
    # (low-confidence mode, an unrecognized format sent to
    # Ingest::LoaderDrafter, or a failed draft attempt). Mirrors
    # PgReviewQueueRepository's shape deliberately (see
    # db/migrations/009_create_ingest_review_entries.rb's own comment) so
    # a future UI/CLI review subcommand needs no schema change.
    #
    # Not a Core::Ports adapter, same reasoning as PgReviewQueueRepository:
    # no current second consumer needs a swappable backend for this
    # admin/HITL flow.
    class PgIngestReviewRepository
      # @param db [Sequel::Database]
      def initialize(db)
        @db = db
      end

      # @param path [String]
      # @param status [String] "pending" | "low_confidence_mode" | "loader_drafted" | "draft_failed"
      # @param reasoning [String]
      # @param format [String, nil]
      # @param mode [String, nil]
      # @param confidence [Float, nil]
      # @param loader_path [String, nil] set when status: "loader_drafted"
      # @param doc_path [String, nil] set when status: "loader_drafted"
      # @return [String] the new row's id
      # rubocop:disable Metrics/ParameterLists -- eight independent scalar fields on an
      # insert-only row, same shape as PgReviewQueueRepository#enqueue, no natural grouping.
      def enqueue(path:, reasoning:, status: "pending", format: nil, mode: nil, confidence: nil,
        loader_path: nil, doc_path: nil
      )
        id = SecureRandom.uuid
        @db[:ingest_review_entries].insert(
          id:, path: path.to_s, status: status.to_s, format: format&.to_s, mode: mode&.to_s,
          confidence:, reasoning: reasoning.to_s, loader_path:, doc_path:, created_at: Time.now
        )
        id
      end
      # rubocop:enable Metrics/ParameterLists

      # @param id [String]
      # @return [Hash, nil] the row, nil if not found
      def find(id)
        @db[:ingest_review_entries].where(id:).first
      end

      # @param path [String]
      # @return [Boolean] true if a row for this exact path exists with status "resolved"
      def resolved?(path)
        @db[:ingest_review_entries].where(path: path.to_s, status: "resolved").any?
      end
    end
  end
end
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/store/pg_ingest_review_repository_spec.rb`
Expected: PASS (8 examples)

- [ ] **Step 5: Rubocop**

Run: `bundle exec rubocop lib/sfl/store/pg_ingest_review_repository.rb spec/store/pg_ingest_review_repository_spec.rb`
Expected: no offenses

- [ ] **Step 6: Commit**

```bash
git add lib/sfl/store/pg_ingest_review_repository.rb spec/store/pg_ingest_review_repository_spec.rb
git commit -m "feat(store): add PgIngestReviewRepository"
```

---

### Task 3: `Core::Types::ClassificationResult`

**Files:**
- Create: `lib/sfl/core/types/classification_result.rb`
- Test: `spec/core/types/classification_result_spec.rb`

**Interfaces:**
- Produces: `Core::Types::ClassificationResult.new(format:, mode:, confidence:, reasoning:)` — a `Dry::Struct` with `format: Core::Types::String`, `mode: Core::Types::String.optional`, `confidence: Core::Types::Coercible::Float.constrained(gteq: 0.0, lteq: 1.0)`, `reasoning: Core::Types::String`. Consumed by Task 4 (`Core::Ports::Classifier`), Task 6 (`LLM::Classifier`), Task 9 (`Ingest::Orchestrator`).
- `format`/`mode` are plain `String`, not `Symbol` — matches how `InterpersonalPayload#mood`/`TextualPayload#theme_type` are stored (`lib/sfl/llm/engine.rb:152-154`, `:216-222`), and avoids the LLM-boundary Symbol-coercion issue `PgReviewQueueRepository#enqueue`'s doc comment already flags for this exact class of value (`lib/sfl/store/pg_review_queue_repository.rb:40-46`).

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/core/types/classification_result_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Types::ClassificationResult do
  it "builds from format/mode/confidence/reasoning" do
    result = described_class.new(
      format: "markdown_chat", mode: "conversation", confidence: 0.4,
      reasoning: "Has speaker-labeled lines but also prose paragraphs"
    )

    expect(result.format).to eq("markdown_chat")
    expect(result.mode).to eq("conversation")
    expect(result.confidence).to eq(0.4)
  end

  it "allows a nil mode (format recognized, mode undetermined)" do
    result = described_class.new(
      format: "unknown", mode: nil, confidence: 0.2, reasoning: "no loader recognizes this shape"
    )

    expect(result.mode).to be_nil
  end

  it "coerces an Integer confidence to Float (LLM-boundary coercion, same rationale as " \
    "ReasoningTrace#confidence)" do
    result = described_class.new(format: "markdown", mode: "documentation", confidence: 1, reasoning: "r")

    expect(result.confidence).to eq(1.0)
  end

  it "rejects a confidence outside 0.0..1.0" do
    expect do
      described_class.new(format: "markdown", mode: "documentation", confidence: 1.5, reasoning: "r")
    end.to raise_error(Dry::Struct::Error)
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/core/types/classification_result_spec.rb`
Expected: FAIL with `uninitialized constant SFL::Core::Types::ClassificationResult`

- [ ] **Step 3: Write the implementation**

```ruby
# lib/sfl/core/types/classification_result.rb
# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Ingest::DeterministicRules/Core::Ports::Classifier's verdict on one
      # file: which format it looks like, which of the three existing
      # analysis modes (conversation/knowledge_base/documentation) it
      # should dispatch to, and how confident that verdict is. Mirrors the
      # existing ReasoningTrace pattern (lib/sfl/core/types/reasoning_trace.rb)
      # so classification decisions are auditable the same way Pass 2
      # annotation decisions already are — `reasoning` is always present,
      # never optional.
      #
      # format/mode are plain String, not Symbol: matches how
      # InterpersonalPayload#mood/TextualPayload#theme_type are already
      # stored, and avoids the Symbol-at-a-Postgres-boundary footgun
      # PgReviewQueueRepository#enqueue's own doc comment already flags.
      class ClassificationResult < Dry::Struct
        attribute :format, Types::String
        attribute :mode, Types::String.optional
        # Coercible, not strict Float — same LLM-boundary-integer rationale as
        # ReasoningTrace#confidence (lib/sfl/core/types/reasoning_trace.rb:16-18).
        attribute :confidence, Types::Coercible::Float.constrained(gteq: 0.0, lteq: 1.0)
        attribute :reasoning, Types::String
      end
    end
  end
end
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/core/types/classification_result_spec.rb`
Expected: PASS (4 examples)

- [ ] **Step 5: Rubocop**

Run: `bundle exec rubocop lib/sfl/core/types/classification_result.rb spec/core/types/classification_result_spec.rb`
Expected: no offenses

- [ ] **Step 6: Commit**

```bash
git add lib/sfl/core/types/classification_result.rb spec/core/types/classification_result_spec.rb
git commit -m "feat(core): add ClassificationResult type"
```

---

### Task 4: `Core::Ports::Classifier` + `Null`/`Fake` adapters

**Files:**
- Create: `lib/sfl/core/ports/classifier.rb`
- Create: `lib/sfl/core/ports/null/classifier.rb`
- Create: `lib/sfl/core/ports/fake/classifier.rb`
- Modify: `spec/support/shared_examples/ports.rb` (add `"a classifier port"` shared example)
- Modify: `spec/core/ports/null_adapters_spec.rb` (add `Null::Classifier` block)
- Modify: `spec/core/ports/fake_adapters_spec.rb` (add `Fake::Classifier` block)

**Interfaces:**
- Consumes: `Core::Types::ClassificationResult` (Task 3).
- Produces: `Core::Ports::Classifier` module with `#classify(sample) -> Core::Types::ClassificationResult`; `Null::Classifier.new` (always returns `format: "unknown", mode: nil, confidence: 0.0, reasoning: "..."`, matching `Null::Embedder`'s "no-op, safe default" spirit); `Fake::Classifier.new(results: {})` (returns a caller-registered `ClassificationResult` per exact `sample` string, or a low-confidence default — mirrors `Fake::Embedder`'s `vectors:`/`default:` shape). Consumed by Task 6 (`LLM::Classifier` includes this port) and Task 9 (`Ingest::Orchestrator`).

- [ ] **Step 1: Write the failing specs**

Read `spec/support/shared_examples/ports.rb` first, then add this shared example (following the existing `"an embedder port"` example's placement/style, `lib/sfl/... :47-56` in that file):

```ruby
RSpec.shared_examples "a classifier port" do
  it "returns a Core::Types::ClassificationResult from #classify" do
    expect(subject.classify("some file sample")).to be_a(SFL::Core::Types::ClassificationResult)
  end
end
```

Read `spec/core/ports/null_adapters_spec.rb` first, then add (following the file's existing per-class `RSpec.describe` block pattern):

```ruby
RSpec.describe SFL::Core::Ports::Null::Classifier do
  subject { described_class.new }

  it_behaves_like "a classifier port"

  it "always returns format unknown, mode nil, confidence 0.0" do
    result = subject.classify("anything")

    expect(result.format).to eq("unknown")
    expect(result.mode).to be_nil
    expect(result.confidence).to eq(0.0)
  end
end
```

Read `spec/core/ports/fake_adapters_spec.rb` first, then add:

```ruby
RSpec.describe SFL::Core::Ports::Fake::Classifier do
  subject { described_class.new(results:) }

  let(:results) do
    { "chatgpt-shaped sample" => SFL::Core::Types::ClassificationResult.new(
      format: "chatgpt_export", mode: "conversation", confidence: 0.95, reasoning: "has a mapping key"
    ) }
  end

  it_behaves_like "a classifier port"

  it "returns the registered result for an exact sample match" do
    result = subject.classify("chatgpt-shaped sample")

    expect(result.format).to eq("chatgpt_export")
    expect(result.confidence).to eq(0.95)
  end

  it "returns a low-confidence unknown default for an unregistered sample" do
    result = subject.classify("never registered")

    expect(result.format).to eq("unknown")
    expect(result.confidence).to eq(0.0)
  end
end
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `bundle exec rspec spec/core/ports/null_adapters_spec.rb spec/core/ports/fake_adapters_spec.rb`
Expected: FAIL with `uninitialized constant SFL::Core::Ports::Classifier` (and `Null::Classifier`/`Fake::Classifier`)

- [ ] **Step 3: Write the port**

```ruby
# lib/sfl/core/ports/classifier.rb
# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Ingest-time classification port: given a text sample from a file
      # (not necessarily the whole file — see Ingest::Orchestrator's own
      # sample-size decision), decides which format it looks like and
      # which of the three existing analysis modes it should dispatch to.
      # Only called when Ingest::DeterministicRules finds no match — this
      # port exists for the ambiguous/new-format tail, not the common
      # case (see that module's own comment).
      module Classifier
        # @param sample [String]
        # @return [SFL::Core::Types::ClassificationResult]
        def classify(sample)
          raise NotImplementedError, "#{self.class} must implement #classify"
        end
      end
    end
  end
end
```

- [ ] **Step 4: Write the Null adapter**

```ruby
# lib/sfl/core/ports/null/classifier.rb
# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # No-op Classifier: always returns the lowest-confidence "unknown"
        # verdict, so a caller that hasn't wired a real Classifier in
        # (e.g. an unrelated spec) always falls through to
        # Ingest::Orchestrator's review/draft path rather than silently
        # dispatching anywhere.
        class Classifier
          include Ports::Classifier

          def classify(_sample)
            Types::ClassificationResult.new(
              format: "unknown", mode: nil, confidence: 0.0, reasoning: "Null::Classifier: no real classifier configured"
            )
          end
        end
      end
    end
  end
end
```

- [ ] **Step 5: Write the Fake adapter**

```ruby
# lib/sfl/core/ports/fake/classifier.rb
# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Fake
        # Deterministic Classifier for specs that need controllable
        # classification output without a real LLM call — mirrors
        # Fake::Embedder's vectors:/default: shape (results keyed by exact
        # sample text; anything unregistered gets a caller-supplied
        # default, defaulting to the same "unknown" verdict
        # Null::Classifier returns).
        class Classifier
          include Ports::Classifier

          def initialize(results: {}, default: Types::ClassificationResult.new(
            format: "unknown", mode: nil, confidence: 0.0, reasoning: "Fake::Classifier: no result registered for this sample"
          ))
            @results = results
            @default = default
          end

          def classify(sample)
            @results.fetch(sample, @default)
          end
        end
      end
    end
  end
end
```

- [ ] **Step 6: Run the specs to verify they pass**

Run: `bundle exec rspec spec/core/ports/null_adapters_spec.rb spec/core/ports/fake_adapters_spec.rb`
Expected: PASS (all examples, including the pre-existing ones in both files)

- [ ] **Step 7: Rubocop**

Run: `bundle exec rubocop lib/sfl/core/ports/classifier.rb lib/sfl/core/ports/null/classifier.rb lib/sfl/core/ports/fake/classifier.rb spec/support/shared_examples/ports.rb spec/core/ports/null_adapters_spec.rb spec/core/ports/fake_adapters_spec.rb`
Expected: no offenses

- [ ] **Step 8: Commit**

```bash
git add lib/sfl/core/ports/classifier.rb lib/sfl/core/ports/null/classifier.rb \
  lib/sfl/core/ports/fake/classifier.rb spec/support/shared_examples/ports.rb \
  spec/core/ports/null_adapters_spec.rb spec/core/ports/fake_adapters_spec.rb
git commit -m "feat(core): add Classifier port + Null/Fake adapters"
```

---

### Task 5: `Ingest::DeterministicRules`

**Files:**
- Create: `lib/sfl/ingest/deterministic_rules.rb`
- Test: `spec/ingest/deterministic_rules_spec.rb`

**Interfaces:**
- Consumes: `Analysis::ChatExportExpander.detect_format` (`lib/sfl/analysis/chat_export_expander.rb:37`), `Analysis::KnowledgeBaseSource::TEXT_EXTENSIONS`/`IMAGE_EXTENSIONS` (`lib/sfl/analysis/knowledge_base_source.rb:53-54`).
- Produces: `Ingest::DeterministicRules.classify(path) -> {format:, mode:, source_type:} | nil`. Consumed by Task 9 (`Ingest::Orchestrator`).

**Design note — deviation from the approved spec's exact return-shape sketch:** the spec document sketches `#classify(path) → {format:, mode:, loader_class:} | nil`. Deeper investigation while planning found that `Analysis::ConversationSource`, `Analysis::DocumentationSource`, and `Analysis::KnowledgeBaseSource` **each already do their own extension/format dispatch internally** (`documentation_source.rb:121`, `knowledge_base_source.rb:178`) — the mode-specific engine resolves its own loader once `Ingest::Orchestrator` hands it a path. A `loader_class:` key would be redundant and never actually used by the orchestrator. This task returns `source_type:` instead (a plain String tag, e.g. `"chat_native"`/`"chat_chatgpt"`/`"vault_markdown"`, matching the tagging convention `gather_conversation_files`/`KnowledgeBaseSource#source_type_for` already use) — `mode` alone is what Task 9 needs to pick which of the three existing engines to call. This doesn't change the architecture or component list from the approved spec, only this one internal return shape.

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/ingest/deterministic_rules_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe SFL::Ingest::DeterministicRules do
  around do |example|
    Dir.mktmpdir { |dir| @tmpdir = dir; example.run }
  end

  def write(name, content)
    path = File.join(@tmpdir, name)
    File.write(path, content)
    path
  end

  describe ".classify" do
    it "matches a .md file as knowledge_base/documentation-shaped" do
      path = write("notes.md", "# Title\n\nSome text.")

      result = described_class.classify(path)

      expect(result).to eq(format: "markdown", mode: "knowledge_base", source_type: "vault_markdown")
    end

    it "matches a .pdf file" do
      path = write("doc.pdf", "%PDF-1.4 fake")

      result = described_class.classify(path)

      expect(result).to include(format: "pdf", mode: "knowledge_base", source_type: "vault_pdf")
    end

    it "matches a .canvas file" do
      path = write("board.canvas", "{}")

      result = described_class.classify(path)

      expect(result).to include(format: "canvas", mode: "knowledge_base", source_type: "vault_canvas")
    end

    it "matches a native chat file (.jsonl) as conversation-shaped" do
      path = write("chat.jsonl", %({"name":"a","mes":"hi","send_date":"2026-01-01"}\n))

      result = described_class.classify(path)

      expect(result).to eq(format: "chat_native", mode: "conversation", source_type: "chat_native")
    end

    it "matches a ChatGPT export .json (mapping key) as conversation-shaped" do
      path = write("export.json", %({"mapping": {"a": {"message": null}}}))

      result = described_class.classify(path)

      expect(result).to eq(format: "chatgpt_export", mode: "conversation", source_type: "chat_chatgpt")
    end

    it "matches a Claude export .json (chat_messages key) as conversation-shaped" do
      path = write("export.json", %({"chat_messages": [{"text": "hi"}]}))

      result = described_class.classify(path)

      expect(result).to eq(format: "claude_export", mode: "conversation", source_type: "chat_claude")
    end

    it "returns nil for an unrecognized .json shape" do
      path = write("data.json", %({"unrelated": "shape"}))

      expect(described_class.classify(path)).to be_nil
    end

    it "returns nil for an unrecognized extension (e.g. .jsonl-like new export format)" do
      path = write("weird_chat.ndjson", %({"role": "user", "content": "hi"}\n))

      expect(described_class.classify(path)).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/ingest/deterministic_rules_spec.rb`
Expected: FAIL with `uninitialized constant SFL::Ingest::DeterministicRules`

- [ ] **Step 3: Write the implementation**

```ruby
# lib/sfl/ingest/deterministic_rules.rb
# frozen_string_literal: true

module SFL
  module Ingest
    # Free/instant fast-path classification: the extension- and JSON-key-
    # sniffing checks Analysis::ChatExportExpander/Analysis::KnowledgeBaseSource
    # already implement, unified into one entry point Ingest::Orchestrator
    # consults before ever calling Core::Ports::Classifier. Behavior is
    # unchanged from today for every already-supported file type — this
    # module delegates to (not reimplements) the existing dispatch logic,
    # so there is exactly one place each of those rules lives.
    module DeterministicRules
      NATIVE_CHAT_EXTENSIONS = %w[.jsonl .srt .vtt .ass].freeze

      KB_EXTENSION_FORMATS = {
        ".md" => "markdown",
        ".canvas" => "canvas",
        ".pdf" => "pdf",
      }.freeze

      KB_EXTENSION_SOURCE_TYPES = {
        ".md" => "vault_markdown",
        ".canvas" => "vault_canvas",
        ".pdf" => "vault_pdf",
      }.freeze

      # @param path [String]
      # @return [Hash{format:, mode:, source_type:}, nil] nil = no deterministic match,
      #   caller should fall through to Core::Ports::Classifier
      module_function def classify(path)
        ext = File.extname(path).downcase

        return classify_native_chat if NATIVE_CHAT_EXTENSIONS.include?(ext)
        return classify_kb_extension(ext) if KB_EXTENSION_FORMATS.key?(ext)
        return classify_image(ext) if Core::Loaders::ImageSource::SUPPORTED_EXTENSIONS.include?(ext)
        return classify_json_export(path) if ext == ".json"

        nil
      end

      module_function def classify_native_chat
        { format: "chat_native", mode: "conversation", source_type: "chat_native" }
      end

      module_function def classify_kb_extension(ext)
        { format: KB_EXTENSION_FORMATS.fetch(ext), mode: "knowledge_base", source_type: KB_EXTENSION_SOURCE_TYPES.fetch(ext) }
      end

      module_function def classify_image(_ext)
        { format: "image", mode: "knowledge_base", source_type: "vault_image" }
      end

      # Delegates to Analysis::ChatExportExpander's existing JSON-key sniff
      # (lib/sfl/analysis/chat_export_expander.rb:37-47) rather than
      # re-reading/re-parsing the file a second time with different logic.
      module_function def classify_json_export(path)
        format = Analysis::ChatExportExpander.detect_format(path)
        case format
        when :chatgpt then { format: "chatgpt_export", mode: "conversation", source_type: "chat_chatgpt" }
        when :claude then { format: "claude_export", mode: "conversation", source_type: "chat_claude" }
        end
      rescue Core::Loaders::Error
        nil # malformed/unparseable JSON is not a deterministic match — fall through to the classifier
      end
    end
  end
end
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/ingest/deterministic_rules_spec.rb`
Expected: PASS (8 examples)

- [ ] **Step 5: Rubocop**

Run: `bundle exec rubocop lib/sfl/ingest/deterministic_rules.rb spec/ingest/deterministic_rules_spec.rb`
Expected: no offenses

- [ ] **Step 6: Commit**

```bash
git add lib/sfl/ingest/deterministic_rules.rb spec/ingest/deterministic_rules_spec.rb
git commit -m "feat(ingest): add DeterministicRules fast-path classifier"
```

---

### Task 6: `LLM::Classifier` (real `Core::Ports::Classifier` adapter)

**Files:**
- Create: `lib/sfl/llm/schemas/classification_schema.rb`
- Create: `lib/sfl/prompts/templates/ingest_classification.txt.erb`
- Create: `lib/sfl/llm/classifier.rb`
- Test: `spec/llm/classifier_spec.rb`

**Interfaces:**
- Consumes: `Core::Ports::Classifier` (Task 4), `Core::Types::ClassificationResult` (Task 3), `Prompts.render` (`lib/sfl/prompts.rb:19`), `LLM::ResponseSymbolizer.call` (`lib/sfl/llm/response_symbolizer.rb:10`), `Core::Ports::Breaker`/`Null::Breaker`, `Core::Ports::Logger`/`Null::Logger`.
- Produces: `LLM::Classifier.new(chat:, breaker: Core::Ports::Null::Breaker.new, logger: Core::Ports::Null::Logger.new)`, `#classify(sample) -> Core::Types::ClassificationResult`. Consumed by Task 7 (`Boot.build_classifier`) and Task 9.

- [ ] **Step 1: Write the schema**

```ruby
# lib/sfl/llm/schemas/classification_schema.rb
# frozen_string_literal: true

require "ruby_llm/schema"

module SFL
  module LLM
    module Schemas
      # Structured-output contract for Ingest classification — mirrors
      # ClauseAnnotationSchema's shape (enum constraints, a required
      # reasoning field) so the "contract rejection over silent
      # scale-guessing" convention (F6/D9) extends to this new LLM call
      # site too: an out-of-range confidence is a schema violation
      # LLM::Classifier rejects, not a value to silently clamp.
      class ClassificationSchema < RubyLLM::Schema
        string :format, description: "A short lowercase_with_underscores tag for the detected file format, " \
          "e.g. chatgpt_export, markdown_chat, generic_jsonl_chat, unknown"
        string :mode, required: false,
          enum: %w[conversation knowledge_base documentation],
          description: "Which existing analysis mode this file belongs to, omitted if undeterminable"
        number :confidence, description: "Confidence in this classification, 0.0-1.0", minimum: 0.0, maximum: 1.0
        string :reasoning, description: "Step-by-step reasoning for the format/mode classification"
      end
    end
  end
end
```

- [ ] **Step 2: Write the prompt template**

```erb
Classify this file sample for an ingest pipeline that routes files to one of three analysis
modes: "conversation" (chat/dialogue transcripts), "knowledge_base" (reference documents,
notes, articles), or "documentation" (technical docs, specs, READMEs).

File path: <%= path %>

Sample content (may be truncated):
---
<%= sample %>
---

Report a short format tag (e.g. chatgpt_export, markdown_chat, generic_jsonl_chat, unknown),
which mode this belongs to (omit if you cannot tell), your confidence 0.0-1.0, and your
reasoning. If the content doesn't look like any recognizable file format at all, use format
"unknown" and omit mode.
```

Save as `lib/sfl/prompts/templates/ingest_classification.txt.erb`.

- [ ] **Step 3: Write the failing spec**

```ruby
# spec/llm/classifier_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::LLM::Classifier do
  subject(:classifier) { described_class.new(chat:) }

  let(:chat) { double("chat") } # rubocop:disable RSpec/VerifiedDoubles -- duck-typed #with_schema seam, same rationale as ClauseAnnotator's chat: double
  let(:schema_chat) { double("schema_chat") } # rubocop:disable RSpec/VerifiedDoubles

  before { allow(chat).to receive(:with_schema).with(SFL::LLM::Schemas::ClassificationSchema).and_return(schema_chat) }

  describe "#classify" do
    it "returns a ClassificationResult built from the LLM's structured response" do
      response = instance_double(RubyLLM::Message, content: {
        "format" => "generic_jsonl_chat", "mode" => nil, "confidence" => 0.2,
        "reasoning" => "JSONL rows resembling a chat log, but no loader recognizes this shape",
      })
      allow(schema_chat).to receive(:ask).and_return(response)

      result = classifier.classify("path: weird_chat.jsonl\n...")

      expect(result).to be_a(SFL::Core::Types::ClassificationResult)
      expect(result.format).to eq("generic_jsonl_chat")
      expect(result.mode).to be_nil
      expect(result.confidence).to eq(0.2)
    end

    it "returns a low-confidence unknown result, not a raised error, when the LLM call fails" do
      allow(schema_chat).to receive(:ask).and_raise(RubyLLM::Error, "rate limited")

      result = classifier.classify("some sample")

      expect(result.format).to eq("unknown")
      expect(result.confidence).to eq(0.0)
      expect(result.reasoning).to include("rate limited")
    end
  end
end
```

- [ ] **Step 4: Run the spec to verify it fails**

Run: `bundle exec rspec spec/llm/classifier_spec.rb`
Expected: FAIL with `uninitialized constant SFL::LLM::Classifier`

- [ ] **Step 5: Write the implementation**

```ruby
# lib/sfl/llm/classifier.rb
# frozen_string_literal: true

module SFL
  module LLM
    # Real Core::Ports::Classifier adapter: sends a file sample to an LLM
    # (tier: ingest_classification — see SFL::Boot) constrained by
    # Schemas::ClassificationSchema. Wrapped in a Breaker the same way
    # Embedder/Engine already are — a failed/timed-out call degrades to a
    # confidence-0.0 "unknown" result rather than raising, so
    # Ingest::Orchestrator's caller-facing contract never has to
    # special-case a Classifier exception (the low-confidence path already
    # handles this uniformly).
    class Classifier
      include Core::Ports::Classifier

      # @param chat [#with_schema] a RubyLLM::Chat (or compatible double)
      # @param breaker [#call] Core::Ports::Breaker-compatible
      # @param logger [#debug,#info,#warn,#error] Core::Ports::Logger-compatible
      def initialize(chat:, breaker: Core::Ports::Null::Breaker.new, logger: Core::Ports::Null::Logger.new)
        @chat = chat
        @breaker = breaker
        @logger = logger
      end

      # @param sample [String]
      # @return [Core::Types::ClassificationResult]
      def classify(sample)
        raw = breaker.call("classifier.classify") { fetch(sample) }
        Core::Types::ClassificationResult.new(
          format: raw[:format], mode: raw[:mode], confidence: raw[:confidence], reasoning: raw[:reasoning]
        )
      rescue => e
        logger.warn { "ingest classifier failed: #{e.class}: #{e.message}" }
        Core::Types::ClassificationResult.new(
          format: "unknown", mode: nil, confidence: 0.0, reasoning: "Classification failed: #{e.message}"
        )
      end

      attr_reader :chat, :breaker, :logger
      private :chat, :breaker, :logger

      private def fetch(sample)
        prompt = Prompts.render(:ingest_classification, path: "(sample)", sample:)
        response = chat.with_schema(Schemas::ClassificationSchema).ask(prompt)
        ResponseSymbolizer.call(response.content)
      end
    end
  end
end
```

- [ ] **Step 6: Run the spec to verify it passes**

Run: `bundle exec rspec spec/llm/classifier_spec.rb`
Expected: PASS (2 examples)

- [ ] **Step 7: Rubocop**

Run: `bundle exec rubocop lib/sfl/llm/schemas/classification_schema.rb lib/sfl/llm/classifier.rb spec/llm/classifier_spec.rb`
Expected: no offenses

- [ ] **Step 8: Commit**

```bash
git add lib/sfl/llm/schemas/classification_schema.rb lib/sfl/prompts/templates/ingest_classification.txt.erb \
  lib/sfl/llm/classifier.rb spec/llm/classifier_spec.rb
git commit -m "feat(llm): add LLM::Classifier adapter for ingest classification"
```

---

### Task 7: `SFL::Boot` wiring — `ingest_classification` + `loader_drafting` task configs

**Files:**
- Modify: `lib/sfl/boot.rb:50` (`TASK_NAMES`), `:155-181` (`call`), `:184-193` (`build_llm_collaborators`), `:206-216` (`build_llm_config`)
- Test: `spec/boot/boot_spec.rb` (add examples for the two new tasks + `Boot::Result#classifier`)

**Interfaces:**
- Consumes: `LLM::Classifier` (Task 6), `task_config_from_env` (`lib/sfl/boot.rb:229`, unchanged).
- Produces: `Boot::Result#classifier -> LLM::Classifier`, plus `llm_config.for(:ingest_classification)`/`llm_config.for(:loader_drafting)` become valid calls. `Boot::Result#loader_drafting_task -> LLM::TaskConfig` is exposed directly (not built into a collaborator object here — Task 8's `Ingest::LoaderDrafter` builds its own chat via `chat_factory.for(:loader_drafting)`, exactly like `build_kb_source` already does for `:context_synthesis` in `cli.rb:462`).

**Design note:** `ingest_classification` defaults to the same provider/model as `:embedding` (cheap tier) since this codebase's Boot module doesn't yet have a "cheap chat model" default distinct from Pass 2's default — reusing `:embedding`'s default is a defensible cheap-tier starting point, same judgment call `:context_synthesis` already makes by reusing `:pass_two_annotation`'s default (`lib/sfl/boot.rb:61-66`). `loader_drafting` defaults to the same default as `:pass_two_annotation` (a stronger general-purpose model) since there is no existing "reasoning-tier" default to borrow from yet.

- [ ] **Step 1: Read `lib/sfl/boot.rb` and `spec/boot/boot_spec.rb` in full** (required before editing; both files are read in earlier planning steps of this document but must be re-read fresh in the implementing session).

- [ ] **Step 2: Write the failing spec additions**

Add to `spec/boot/boot_spec.rb` (inside the existing `RSpec.describe SFL::Boot` block, following its established `boot(env:, **overrides)` helper):

```ruby
  describe "ingest_classification and loader_drafting task configs" do
    it "defaults ingest_classification to the embedding task's default provider/model" do
      result = boot(env: base_env.merge("EMBEDDING_MODEL" => "embeddinggemma:latest"))

      task = result.llm_config.for(:ingest_classification)
      expect(task.provider).to eq(:ollama)
      expect(task.model).to eq("embeddinggemma:latest")
    end

    it "honors SFL_TASK_INGEST_CLASSIFICATION_MODEL/_PROVIDER overrides" do
      result = boot(env: base_env.merge(
        "SFL_TASK_INGEST_CLASSIFICATION_MODEL" => "custom-cheap-model",
        "SFL_TASK_INGEST_CLASSIFICATION_PROVIDER" => "openrouter"
      ))

      task = result.llm_config.for(:ingest_classification)
      expect(task.provider).to eq(:openrouter)
      expect(task.model).to eq("custom-cheap-model")
    end

    it "defaults loader_drafting to the same default provider/model as pass_two_annotation" do
      result = boot(env: base_env)

      pass_two = result.llm_config.for(:pass_two_annotation)
      loader_drafting = result.llm_config.for(:loader_drafting)
      expect(loader_drafting.provider).to eq(pass_two.provider)
      expect(loader_drafting.model).to eq(pass_two.model)
    end

    it "honors SFL_TASK_LOADER_DRAFTING_MODEL/_PROVIDER overrides" do
      result = boot(env: base_env.merge(
        "SFL_TASK_LOADER_DRAFTING_MODEL" => "custom-reasoning-model",
        "SFL_TASK_LOADER_DRAFTING_PROVIDER" => "anthropic"
      ))

      task = result.llm_config.for(:loader_drafting)
      expect(task.provider).to eq(:anthropic)
      expect(task.model).to eq("custom-reasoning-model")
    end
  end

  describe "Result#classifier" do
    it "builds an LLM::Classifier wired to the ingest_classification task" do
      result = boot(env: base_env)

      expect(result.classifier).to be_a(SFL::LLM::Classifier)
    end
  end
```

(`base_env` already sets `DATABASE_URL`/`OPENROUTER_API_KEY`, per `spec/boot/boot_spec.rb`'s existing `let(:base_env)`.)

- [ ] **Step 3: Run the spec to verify it fails**

Run: `bundle exec rspec spec/boot/boot_spec.rb`
Expected: FAIL — `for(:ingest_classification)`/`for(:loader_drafting)` raise `SFL::LLM::Error` (unregistered task), `result.classifier` raises `NoMethodError`

- [ ] **Step 4: Update `TASK_NAMES`**

In `lib/sfl/boot.rb`, change:

```ruby
    TASK_NAMES = %i[pass_two_annotation pass_two_batch_annotation context_synthesis embedding].freeze
```

to:

```ruby
    TASK_NAMES = %i[
      pass_two_annotation pass_two_batch_annotation context_synthesis embedding
      ingest_classification loader_drafting
    ].freeze
```

- [ ] **Step 5: Add the two task configs to `build_llm_config`**

Change (`lib/sfl/boot.rb:206-216`):

```ruby
    module_function def build_llm_config(env)
      pass_two_annotation = pass_two_task_config(:pass_two_annotation, env)
      pass_two_batch_annotation = pass_two_task_config(:pass_two_batch_annotation, env)
      context_synthesis = task_config_from_env(
        :context_synthesis, env,
        default_provider: pass_two_annotation.provider, default_model: pass_two_annotation.model
      )
      embedding = embedding_task_config(env)

      LLM::Config.new(tasks: { pass_two_annotation:, pass_two_batch_annotation:, context_synthesis:, embedding: })
    end
```

to:

```ruby
    module_function def build_llm_config(env)
      pass_two_annotation = pass_two_task_config(:pass_two_annotation, env)
      pass_two_batch_annotation = pass_two_task_config(:pass_two_batch_annotation, env)
      context_synthesis = task_config_from_env(
        :context_synthesis, env,
        default_provider: pass_two_annotation.provider, default_model: pass_two_annotation.model
      )
      embedding = embedding_task_config(env)
      # No existing "cheap chat model" default to borrow from — :embedding's default is the
      # cheapest task already configured, same defensible-starting-point judgment call
      # :context_synthesis makes above by reusing :pass_two_annotation's default.
      ingest_classification = task_config_from_env(
        :ingest_classification, env, default_provider: embedding.provider, default_model: embedding.model
      )
      # No existing "reasoning tier" default either — :pass_two_annotation's default is the
      # strongest general-purpose task already configured.
      loader_drafting = task_config_from_env(
        :loader_drafting, env,
        default_provider: pass_two_annotation.provider, default_model: pass_two_annotation.model
      )

      LLM::Config.new(tasks: {
        pass_two_annotation:, pass_two_batch_annotation:, context_synthesis:, embedding:,
        ingest_classification:, loader_drafting:,
      })
    end
```

- [ ] **Step 6: Build the `LLM::Classifier` collaborator and expose it on `Boot::Result`**

Read `lib/sfl/boot/result.rb` first. Add a `classifier:` attribute to `Boot::Result` following the exact pattern its existing attributes (`db:`, `embedder:`, etc.) already use.

In `lib/sfl/boot.rb`, change `build_llm_collaborators` (`:184-193`):

```ruby
    module_function def build_llm_collaborators(env, ruby_llm)
      llm_config = build_llm_config(env)
      validate_api_keys!(llm_config, env)
      configure_ruby_llm_providers(llm_config, env, ruby_llm)

      chat_factory = LLM::ChatFactory.new(config: llm_config)
      embedder = build_embedder(llm_config, env, ruby_llm)

      [llm_config, chat_factory, embedder]
    end
```

to:

```ruby
    module_function def build_llm_collaborators(env, ruby_llm)
      llm_config = build_llm_config(env)
      validate_api_keys!(llm_config, env)
      configure_ruby_llm_providers(llm_config, env, ruby_llm)

      chat_factory = LLM::ChatFactory.new(config: llm_config)
      embedder = build_embedder(llm_config, env, ruby_llm)
      classifier = LLM::Classifier.new(chat: chat_factory.for(:ingest_classification))

      [llm_config, chat_factory, embedder, classifier]
    end
```

Change the `call` method's collaborator-destructuring line (`:167`):

```ruby
      llm_config, chat_factory, embedder = build_llm_collaborators(env, ruby_llm) if require_llm
```

to:

```ruby
      llm_config, chat_factory, embedder, classifier = build_llm_collaborators(env, ruby_llm) if require_llm
```

And its `Result.new(...)` call (`:179-180`):

```ruby
      Result.new(db:, llm_config:, chat_factory:, embedder:, pass1_command:, pass1_env:, spacy_model:,
        api_debug_errors:, api_cors_origins:)
```

to:

```ruby
      Result.new(db:, llm_config:, chat_factory:, embedder:, classifier:, pass1_command:, pass1_env:, spacy_model:,
        api_debug_errors:, api_cors_origins:)
```

- [ ] **Step 7: Run the spec to verify it passes**

Run: `bundle exec rspec spec/boot/boot_spec.rb`
Expected: PASS (all examples, including the 4 pre-existing task-config describe blocks and the new ones)

- [ ] **Step 8: Rubocop**

Run: `bundle exec rubocop lib/sfl/boot.rb lib/sfl/boot/result.rb spec/boot/boot_spec.rb`
Expected: no offenses

- [ ] **Step 9: Commit**

```bash
git add lib/sfl/boot.rb lib/sfl/boot/result.rb spec/boot/boot_spec.rb
git commit -m "feat(boot): wire ingest_classification and loader_drafting task configs"
```

---

### Task 8: `Ingest::LoaderDrafter`

**Files:**
- Create: `lib/sfl/llm/schemas/loader_draft_schema.rb`
- Create: `lib/sfl/prompts/templates/loader_drafting.txt.erb`
- Create: `lib/sfl/ingest/loader_drafter.rb`
- Test: `spec/ingest/loader_drafter_spec.rb`

**Interfaces:**
- Consumes: `Core::Loaders::Source` mixin contract (`lib/sfl/core/loaders/source.rb`), `Prompts.render`, `ResponseSymbolizer`.
- Produces: `Ingest::LoaderDrafter.new(chat:, loaders_dir: "lib/sfl/core/loaders", docs_dir: "docs/ingest-review")`, `#draft(sample, path) -> {loader_path:, doc_path:}`, raising `Ingest::LoaderDrafter::Error` on an LLM/schema failure (caught by Task 9's `Orchestrator`, which records `status: "draft_failed"`). Consumed by Task 9.

- [ ] **Step 1: Write the schema**

```ruby
# lib/sfl/llm/schemas/loader_draft_schema.rb
# frozen_string_literal: true

require "ruby_llm/schema"

module SFL
  module LLM
    module Schemas
      # Structured-output contract for Ingest::LoaderDrafter: a candidate
      # loader class name, its Ruby source implementing the
      # Core::Loaders::Source#each_unit contract, and a human-readable
      # explanation of the proposed field mapping. The drafted source is
      # never executed by this schema/adapter itself — see
      # Ingest::LoaderDrafter's own safety-boundary comment.
      class LoaderDraftSchema < RubyLLM::Schema
        string :class_name, description: "PascalCase class name, e.g. GenericJsonlChatSource"
        string :ruby_source, description: "Complete Ruby source for a class under " \
          "SFL::Core::Loaders implementing #each_unit (yielding SFL::Core::Types::Unit), " \
          "matching the Core::Loaders::Source mixin contract"
        string :field_mapping_explanation, description: "Plain-language explanation of how " \
          "sample fields map to speaker/text/sent_at, and why no existing loader matched"
        number :confidence, description: "Confidence this draft is usable as-is, 0.0-1.0",
          minimum: 0.0, maximum: 1.0
      end
    end
  end
end
```

- [ ] **Step 2: Write the prompt template**

```erb
Draft a candidate Ruby loader for this file, to fit an existing ingest pipeline.

File path: <%= path %>

Sample content (may be truncated):
---
<%= sample %>
---

Existing loaders implement SFL::Core::Loaders::Source (see
lib/sfl/core/loaders/source.rb): a module providing #units built on top of a required
#each_unit method, which must yield SFL::Core::Types::Unit instances. Look at
lib/sfl/core/loaders/json_source.rb as a reference example of the expected shape and style
(frozen_string_literal, module SFL::Core::Loaders namespace, `include Source`).

Write a complete, syntactically valid Ruby class for this specific file shape. Explain your
proposed field mapping (which sample fields become speaker/text/sent_at) and why none of the
existing loaders already matched this shape.
```

Save as `lib/sfl/prompts/templates/loader_drafting.txt.erb`.

- [ ] **Step 3: Write the failing spec**

```ruby
# spec/ingest/loader_drafter_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe SFL::Ingest::LoaderDrafter do
  around do |example|
    Dir.mktmpdir do |dir|
      @loaders_dir = File.join(dir, "loaders")
      @docs_dir = File.join(dir, "docs")
      example.run
    end
  end

  subject(:drafter) { described_class.new(chat:, loaders_dir: @loaders_dir, docs_dir: @docs_dir) }

  let(:chat) { double("chat") } # rubocop:disable RSpec/VerifiedDoubles -- duck-typed #with_schema seam
  let(:schema_chat) { double("schema_chat") } # rubocop:disable RSpec/VerifiedDoubles

  before { allow(chat).to receive(:with_schema).with(SFL::LLM::Schemas::LoaderDraftSchema).and_return(schema_chat) }

  describe "#draft" do
    it "writes a candidate loader file and a review doc, returning both paths" do
      response = instance_double(RubyLLM::Message, content: {
        "class_name" => "GenericJsonlChatSource",
        "ruby_source" => "# frozen_string_literal: true\n\nmodule SFL\n  module Core\n    module Loaders\n" \
          "      class GenericJsonlChatSource\n        include Source\n\n        def each_unit\n" \
          "        end\n      end\n    end\n  end\nend\n",
        "field_mapping_explanation" => "role -> speaker, content -> text, no timestamp field found",
        "confidence" => 0.6,
      })
      allow(schema_chat).to receive(:ask).and_return(response)

      result = drafter.draft("{\"role\":\"user\",\"content\":\"hi\"}\n", "export-dump/weird_chat.jsonl")

      expect(result[:loader_path]).to eq(File.join(@loaders_dir, "generic_jsonl_chat_source.rb"))
      expect(result[:doc_path]).to eq(File.join(@docs_dir, "generic_jsonl_chat_source.md"))
      expect(File.read(result[:loader_path])).to include("class GenericJsonlChatSource")
      expect(File.read(result[:doc_path])).to include("role -> speaker, content -> text")
    end

    it "raises Ingest::LoaderDrafter::Error, without writing files, on an LLM failure" do
      allow(schema_chat).to receive(:ask).and_raise(RubyLLM::Error, "rate limited")

      expect { drafter.draft("sample", "some/path.ndjson") }.to raise_error(described_class::Error, /rate limited/)
      expect(Dir.exist?(@loaders_dir)).to be(false)
    end
  end
end
```

- [ ] **Step 4: Run the spec to verify it fails**

Run: `bundle exec rspec spec/ingest/loader_drafter_spec.rb`
Expected: FAIL with `uninitialized constant SFL::Ingest::LoaderDrafter`

- [ ] **Step 5: Write the implementation**

```ruby
# lib/sfl/ingest/loader_drafter.rb
# frozen_string_literal: true

require "fileutils"

module SFL
  module Ingest
    # Drafts a candidate SFL::Core::Loaders::Source subclass for a file
    # shape Ingest::DeterministicRules/Core::Ports::Classifier couldn't
    # recognize at all (tier: loader_drafting — see SFL::Boot).
    #
    # Safety boundary: never requires, registers, or executes the drafted
    # file. It is written to `loaders_dir` inert — a human must review it,
    # then manually add the `require` and a DeterministicRules table
    # entry before it runs against real data. No code path in this class
    # or Ingest::Orchestrator loads it automatically.
    class LoaderDrafter
      class Error < SFL::Error; end

      # @param chat [#with_schema] a RubyLLM::Chat (or compatible double)
      # @param loaders_dir [String] where candidate loader .rb files are written
      # @param docs_dir [String] where candidate review .md docs are written
      def initialize(chat:, loaders_dir: "lib/sfl/core/loaders", docs_dir: "docs/ingest-review")
        @chat = chat
        @loaders_dir = loaders_dir
        @docs_dir = docs_dir
      end

      # @param sample [String]
      # @param path [String] the original file's path, for the doc's context
      # @return [Hash{loader_path:, doc_path:}]
      # @raise [Error] the LLM call or schema validation failed
      def draft(sample, path)
        raw = fetch(sample, path)
        write_files(raw, path)
      rescue Error
        raise
      rescue => e
        raise Error, "loader draft failed for #{path}: #{e.message}"
      end

      attr_reader :chat, :loaders_dir, :docs_dir
      private :chat, :loaders_dir, :docs_dir

      private def fetch(sample, path)
        prompt = Prompts.render(:loader_drafting, path:, sample:)
        response = chat.with_schema(Schemas::LoaderDraftSchema).ask(prompt)
        LLM::ResponseSymbolizer.call(response.content)
      end

      private def write_files(raw, source_path)
        file_stem = underscore(raw.fetch(:class_name))
        FileUtils.mkdir_p(loaders_dir)
        FileUtils.mkdir_p(docs_dir)

        loader_path = File.join(loaders_dir, "#{file_stem}.rb")
        doc_path = File.join(docs_dir, "#{file_stem}.md")

        File.write(loader_path, raw.fetch(:ruby_source))
        File.write(doc_path, review_doc(raw, source_path))

        { loader_path:, doc_path: }
      end

      private def review_doc(raw, source_path)
        <<~MARKDOWN
          # Candidate loader: #{raw.fetch(:class_name)}

          Drafted for: `#{source_path}`
          Confidence: #{raw.fetch(:confidence)}

          ## Field mapping

          #{raw.fetch(:field_mapping_explanation)}

          ## Status

          **Not registered.** Review `#{underscore(raw.fetch(:class_name))}.rb`, then wire it in:
          add a `require` and a matching entry in `SFL::Ingest::DeterministicRules` before this
          loader runs against real data.
        MARKDOWN
      end

      # PascalCase -> snake_case, no external inflector dependency needed for this one shape.
      private def underscore(class_name)
        class_name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
      end
    end
  end
end
```

- [ ] **Step 6: Run the spec to verify it passes**

Run: `bundle exec rspec spec/ingest/loader_drafter_spec.rb`
Expected: PASS (2 examples)

- [ ] **Step 7: Rubocop**

Run: `bundle exec rubocop lib/sfl/llm/schemas/loader_draft_schema.rb lib/sfl/ingest/loader_drafter.rb spec/ingest/loader_drafter_spec.rb`
Expected: no offenses

- [ ] **Step 8: Commit**

```bash
git add lib/sfl/llm/schemas/loader_draft_schema.rb lib/sfl/prompts/templates/loader_drafting.txt.erb \
  lib/sfl/ingest/loader_drafter.rb spec/ingest/loader_drafter_spec.rb
git commit -m "feat(ingest): add LoaderDrafter for unrecognized file formats"
```

---

### Task 9: `Ingest::Orchestrator`

**Files:**
- Create: `lib/sfl/ingest/orchestrator.rb`
- Test: `spec/ingest/orchestrator_spec.rb`

**Interfaces:**
- Consumes: `Ingest::DeterministicRules.classify` (Task 5), `Core::Ports::Classifier#classify` (Task 4), `Ingest::LoaderDrafter#draft` (Task 8), `Store::PgIngestReviewRepository` (Task 2), `Analysis::Engine#analyze` (`lib/sfl/analysis/engine.rb:76`), `Analysis::KnowledgeBaseSource#analyze` (`lib/sfl/analysis/knowledge_base_source.rb:99`), `Analysis::ConversationSource.new`/`Analysis::DocumentationSource.new`.
- Produces: `Ingest::Orchestrator.new(conversation_engine:, kb_source:, classifier:, loader_drafter:, review_repo:, logger: Core::Ports::Null::Logger.new)`, `#run(path) -> Hash{dispatched:, review_entries:, drafted:}` (per-status counts; `path` may be a single file or a directory, walked recursively). Consumed by Task 10 (`SFL::CLI.run_ingest`).

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/ingest/orchestrator_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe SFL::Ingest::Orchestrator do
  subject(:orchestrator) do
    described_class.new(
      conversation_engine:, kb_source:, classifier:, loader_drafter:, review_repo:
    )
  end

  let(:conversation_engine) { instance_double(SFL::Analysis::Engine, analyze: analysis_result) }
  let(:kb_source) { instance_double(SFL::Analysis::KnowledgeBaseSource, analyze: kb_result) }
  let(:analysis_result) { instance_double(SFL::Core::Types::AnalysisResult, metadata: {}) }
  let(:kb_result) { instance_double(SFL::Core::Types::KnowledgeBaseReport) }
  let(:classifier) { SFL::Core::Ports::Fake::Classifier.new(results: classifier_results) }
  let(:classifier_results) { {} }
  let(:loader_drafter) { instance_double(SFL::Ingest::LoaderDrafter) }
  let(:review_repo) { SFL::Store::PgIngestReviewRepository.new(SFL::Store::StoreTestDb.db) }

  before { SFL::Store::StoreTestDb.clean! }

  around do |example|
    Dir.mktmpdir { |dir| @tmpdir = dir; example.run }
  end

  def write(name, content)
    path = File.join(@tmpdir, name)
    File.write(path, content)
    path
  end

  describe "#run" do
    it "dispatches a deterministically-matched conversation file without calling the classifier" do
      write("chat.jsonl", %({"name":"a","mes":"hi","send_date":"2026-01-01"}\n))
      allow(classifier).to receive(:classify)

      summary = orchestrator.run(@tmpdir)

      expect(conversation_engine).to have_received(:analyze)
      expect(classifier).not_to have_received(:classify)
      expect(summary[:dispatched]).to eq(1)
    end

    it "dispatches a deterministically-matched knowledge_base file to kb_source" do
      write("notes.md", "# Title")

      orchestrator.run(@tmpdir)

      expect(kb_source).to have_received(:analyze)
    end

    it "dispatches via the classifier when a high-confidence verdict is returned for an " \
      "unrecognized extension" do
      path = write("data.ndjson", %({"role":"user","content":"hi"}\n))
      classifier_results[File.read(path)] = SFL::Core::Types::ClassificationResult.new(
        format: "generic_jsonl_chat", mode: "conversation", confidence: 0.9, reasoning: "looks like chat rows"
      )

      summary = orchestrator.run(@tmpdir)

      expect(conversation_engine).to have_received(:analyze)
      expect(summary[:dispatched]).to eq(1)
    end

    it "writes a low_confidence_mode review entry, and does not dispatch, when the format " \
      "is known but the mode is ambiguous" do
      path = write("ambiguous.md", "some pasted chat maybe")
      # .md is a deterministic KB match by extension — force the low-confidence path by
      # stubbing the classifier not to be consulted; instead simulate the ambiguous case via
      # a KB-extension file the deterministic rules would normally match confidently. To
      # exercise the *classifier's* low-confidence branch specifically, use an unrecognized
      # extension whose classifier verdict has a known format but nil/low-confidence mode:
      File.delete(path)
      path = write("ambiguous.unknownext", "some pasted chat maybe")
      classifier_results[File.read(path)] = SFL::Core::Types::ClassificationResult.new(
        format: "markdown", mode: "conversation", confidence: 0.4,
        reasoning: "Has speaker-labeled lines but also prose paragraphs"
      )

      summary = orchestrator.run(@tmpdir)

      expect(conversation_engine).not_to have_received(:analyze)
      expect(kb_source).not_to have_received(:analyze)
      expect(summary[:review_entries]).to eq(1)
      row = review_repo.find(SFL::Store::StoreTestDb.db[:ingest_review_entries].first[:id])
      expect(row[:status]).to eq("low_confidence_mode")
    end

    it "drafts a loader and writes a loader_drafted review entry when format itself is unknown" do
      path = write("weird.unknownext", "totally novel shape")
      classifier_results[File.read(path)] = SFL::Core::Types::ClassificationResult.new(
        format: "unknown", mode: nil, confidence: 0.1, reasoning: "no loader recognizes this shape"
      )
      allow(loader_drafter).to receive(:draft).and_return(
        loader_path: "lib/sfl/core/loaders/x_source.rb", doc_path: "docs/ingest-review/x_source.md"
      )

      summary = orchestrator.run(@tmpdir)

      expect(loader_drafter).to have_received(:draft)
      expect(conversation_engine).not_to have_received(:analyze)
      expect(summary[:drafted]).to eq(1)
      row = review_repo.find(SFL::Store::StoreTestDb.db[:ingest_review_entries].first[:id])
      expect(row[:status]).to eq("loader_drafted")
      expect(row[:loader_path]).to eq("lib/sfl/core/loaders/x_source.rb")
    end

    it "writes a draft_failed review entry, and continues, when LoaderDrafter raises" do
      write("weird.unknownext1", "novel shape one")
      write("weird.unknownext2", "novel shape two")
      classifier_results.default = SFL::Core::Types::ClassificationResult.new(
        format: "unknown", mode: nil, confidence: 0.1, reasoning: "no loader recognizes this shape"
      )
      allow(classifier).to receive(:classify).and_return(classifier_results.default)
      allow(loader_drafter).to receive(:draft).and_raise(SFL::Ingest::LoaderDrafter::Error, "rate limited")

      summary = orchestrator.run(@tmpdir)

      expect(summary[:drafted]).to eq(0)
      expect(summary[:review_entries]).to eq(2)
      rows = SFL::Store::StoreTestDb.db[:ingest_review_entries].all
      expect(rows.map { |r| r[:status] }).to all(eq("draft_failed"))
    end

    it "skips a path whose review entry is already resolved on a rerun" do
      path = write("weird.unknownext", "totally novel shape")
      review_repo.enqueue(path:, status: "resolved", reasoning: "handled by hand", resolved_at: Time.now)
      allow(classifier).to receive(:classify)

      summary = orchestrator.run(@tmpdir)

      expect(classifier).not_to have_received(:classify)
      expect(summary[:dispatched]).to eq(0)
      expect(summary[:review_entries]).to eq(0)
      expect(summary[:drafted]).to eq(0)
    end

    it "continues processing remaining files when one file's dispatch raises (F11 " \
      "partial-failure isolation)" do
      write("a.md", "doc a")
      write("b.md", "doc b")
      allow(kb_source).to receive(:analyze).and_raise(SFL::Analysis::Error, "boom").once
      allow(kb_source).to receive(:analyze).and_return(kb_result)

      summary = orchestrator.run(@tmpdir)

      expect(summary[:dispatched]).to eq(1)
      expect(kb_source).to have_received(:analyze).twice
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/ingest/orchestrator_spec.rb`
Expected: FAIL with `uninitialized constant SFL::Ingest::Orchestrator`

- [ ] **Step 3: Write the implementation**

```ruby
# lib/sfl/ingest/orchestrator.rb
# frozen_string_literal: true

module SFL
  module Ingest
    # Coordinates one ingest run: walks a file or directory, classifies
    # each file (Ingest::DeterministicRules first, Core::Ports::Classifier
    # as fallback), and dispatches matches to the existing, unmodified
    # Analysis::Engine (conversation/documentation) or
    # Analysis::KnowledgeBaseSource — see the design doc's architecture
    # diagram (docs/superpowers/specs/2026-08-06-intelligent-ingest-layer-design.md)
    # for the full decision flow.
    #
    # Low-confidence and unrecognized-format files never get dispatched —
    # they're recorded via Store::PgIngestReviewRepository instead (F11
    # partial-failure isolation: one file's issue never halts the rest of
    # the run, same principle SFL::CLI.run_conversation's own per-file
    # rescue already applies).
    class Orchestrator
      # First N bytes read from each file for classifier/loader-drafter
      # sampling — keeps the LLM call cheap regardless of file size (see
      # the design doc's Data Flow section). Start as a constant, tune
      # later against real large-file corpora.
      SAMPLE_BYTES = 4096

      # Below this, a classifier verdict is treated the same as "no
      # confident match" even when format/mode are both present. Start as
      # a constant, tune later (design doc's Open Questions).
      CONFIDENCE_THRESHOLD = 0.6

      # rubocop:disable Metrics/ParameterLists -- five independently-injectable collaborators
      # (two dispatch targets, the classifier, the drafter, the review repo) plus logger,
      # matching this codebase's existing per-class DI convention (see LLM::Engine#initialize).
      def initialize(
        conversation_engine:, kb_source:, classifier:, loader_drafter:, review_repo:,
        logger: Core::Ports::Null::Logger.new
      )
        @conversation_engine = conversation_engine
        @kb_source = kb_source
        @classifier = classifier
        @loader_drafter = loader_drafter
        @review_repo = review_repo
        @logger = logger
      end
      # rubocop:enable Metrics/ParameterLists

      # @param path [String] a single file, or a directory walked recursively
      # @return [Hash{dispatched:, review_entries:, drafted:}]
      def run(path)
        counts = { dispatched: 0, review_entries: 0, drafted: 0 }
        files(path).each { |file| process(file, counts) }
        logger.info { "ingest run complete: #{counts}" }
        counts
      end

      attr_reader :conversation_engine, :kb_source, :classifier, :loader_drafter, :review_repo, :logger
      private :conversation_engine, :kb_source, :classifier, :loader_drafter, :review_repo, :logger

      private def files(path)
        File.directory?(path) ? Dir.glob(File.join(path, "**", "*")).select { |p| File.file?(p) } : [path]
      end

      # One file's failure must not take the rest of the run down with it — same F11
      # partial-failure-isolation principle SFL::CLI.run_conversation's own per-file rescue
      # already applies (lib/sfl/cli.rb:225-233).
      private def process(file, counts)
        return if review_repo.resolved?(file)

        classification = classify(file)
        dispatch_or_review(file, classification, counts)
      rescue Analysis::Error, Core::Loaders::Error, Store::Error => e
        logger.error { "ingest failed for #{file}: #{e.class}: #{e.message}" }
        review_repo.enqueue(path: file, status: "draft_failed", reasoning: "Dispatch failed: #{e.message}")
        counts[:review_entries] += 1
      end

      private def classify(file)
        deterministic = DeterministicRules.classify(file)
        return deterministic if deterministic

        sample = File.read(file, SAMPLE_BYTES)
        result = classifier.classify(sample)
        { format: result.format, mode: result.mode, confidence: result.confidence, reasoning: result.reasoning }
      end

      private def dispatch_or_review(file, classification, counts)
        if deterministic_or_confident?(classification)
          dispatch(file, classification)
          counts[:dispatched] += 1
        elsif classification[:format] && classification[:format] != "unknown"
          enqueue_low_confidence(file, classification)
          counts[:review_entries] += 1
        else
          draft_or_record_failure(file, classification, counts)
        end
      end

      # A deterministic match (no :confidence key at all) is always dispatched — its
      # confidence is definitionally 1.0, matching today's unchanged extension/JSON-key
      # dispatch behavior. A classifier verdict only dispatches at/above CONFIDENCE_THRESHOLD.
      private def deterministic_or_confident?(classification)
        return true unless classification.key?(:confidence)

        classification[:mode] && classification[:confidence] >= CONFIDENCE_THRESHOLD
      end

      private def dispatch(file, classification)
        case classification[:mode]
        when "conversation"
          source = Analysis::ConversationSource.new(file, source_type: classification[:source_type] || classification[:format])
          conversation_engine.analyze(source, label: File.basename(file, ".*"))
        when "documentation"
          source = Analysis::DocumentationSource.new(file)
          conversation_engine.analyze(source, label: File.basename(file, ".*"))
        when "knowledge_base"
          kb_source.analyze(file)
        end
      end

      private def enqueue_low_confidence(file, classification)
        review_repo.enqueue(
          path: file, status: "low_confidence_mode", format: classification[:format], mode: classification[:mode],
          confidence: classification[:confidence], reasoning: classification[:reasoning]
        )
      end

      private def draft_or_record_failure(file, classification, counts)
        sample = File.read(file, SAMPLE_BYTES)
        draft = loader_drafter.draft(sample, file)
        review_repo.enqueue(
          path: file, status: "loader_drafted", format: classification[:format],
          confidence: classification[:confidence], reasoning: classification[:reasoning],
          loader_path: draft[:loader_path], doc_path: draft[:doc_path]
        )
        counts[:drafted] += 1
      rescue LoaderDrafter::Error => e
        logger.warn { "loader draft failed for #{file}: #{e.message}" }
        review_repo.enqueue(path: file, status: "draft_failed", reasoning: "Draft failed: #{e.message}")
        counts[:review_entries] += 1
      end
    end
  end
end
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/ingest/orchestrator_spec.rb`
Expected: PASS (9 examples). If the "one file's dispatch raises" example is flaky due to file-glob
ordering, sort `Dir.glob`'s result in `files` (`Dir.glob(...).sort`) — add this defensively if the
test run shows nondeterministic ordering across the two `.md` fixtures.

- [ ] **Step 5: Rubocop**

Run: `bundle exec rubocop lib/sfl/ingest/orchestrator.rb spec/ingest/orchestrator_spec.rb`
Expected: no offenses

- [ ] **Step 6: Commit**

```bash
git add lib/sfl/ingest/orchestrator.rb spec/ingest/orchestrator_spec.rb
git commit -m "feat(ingest): add Orchestrator coordinating classify+dispatch+review"
```

---

### Task 10: `sfl-analyze ingest` CLI subcommand

**Files:**
- Modify: `lib/sfl/cli.rb:37-99` (`USAGE`, `parse`), add `parse_ingest_options`, add `run_ingest`, add `build_ingest_orchestrator`
- Test: `spec/cli/parse_spec.rb` (add ingest parsing examples), create `spec/cli/run_ingest_spec.rb`

**Interfaces:**
- Consumes: `Ingest::Orchestrator` (Task 9), `Boot.call` (adds `require_llm: true` since classification needs an LLM), `Store::PgIngestReviewRepository` (Task 2), `SFL::CLI.build_conversation_engine`/`build_kb_source` (existing, `lib/sfl/cli.rb:431-470`, reused unchanged).
- Produces: `sfl-analyze ingest <path> [--output-dir DIR] [--dry-run] [--disable-tracing]`. `--dry-run` classifies every file and prints what *would* happen without calling `Orchestrator#run` at all (no dispatch, no DB writes) — implemented as a separate, simpler code path in `run_ingest`, not a flag threaded through `Orchestrator` itself, keeping `Orchestrator`'s contract side-effecting-by-default and easy to reason about.

- [ ] **Step 1: Read `lib/sfl/cli.rb` in full** (required before editing).

- [ ] **Step 2: Write the failing spec additions**

Add to `spec/cli/parse_spec.rb` (following its existing per-subcommand `describe` block pattern):

```ruby
  describe "ingest" do
    it "parses input and defaults" do
      parsed = described_class.parse(%w[ingest ./export-dump])

      expect(parsed[:command]).to eq(:ingest)
      expect(parsed[:input]).to eq("./export-dump")
      expect(parsed[:options]).to include(output_dir: SFL::CLI::DEFAULT_OUTPUT_DIR, dry_run: false)
    end

    it "parses --dry-run" do
      parsed = described_class.parse(%w[ingest ./export-dump --dry-run])

      expect(parsed[:options][:dry_run]).to be(true)
    end

    it "requires an input argument" do
      expect { described_class.parse(%w[ingest]) }.to raise_error(SFL::CLI::UsageError)
    end
  end
```

Create `spec/cli/run_ingest_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "SFL::CLI.run_ingest" do
  around do |example|
    Dir.mktmpdir { |dir| @tmpdir = dir; example.run }
  end

  it "boots with require_llm: true and runs the orchestrator against the given path" do
    File.write(File.join(@tmpdir, "chat.jsonl"), %({"name":"a","mes":"hi","send_date":"2026-01-01"}\n))
    boot_result = instance_double(
      SFL::Boot::Result, db: nil, llm_config: nil, chat_factory: nil, embedder: nil, classifier: nil,
      pass1_command: nil, pass1_env: nil, spacy_model: "en_core_web_sm", api_debug_errors: false, api_cors_origins: []
    )
    allow(SFL::Boot).to receive(:call).and_return(boot_result)
    orchestrator = instance_double(SFL::Ingest::Orchestrator, run: { dispatched: 1, review_entries: 0, drafted: 0 })
    allow(SFL::CLI).to receive(:build_ingest_orchestrator).and_return(orchestrator)

    SFL::CLI.run_ingest(@tmpdir, { output_dir: "./output/latest", dry_run: false, disable_tracing: true })

    expect(SFL::Boot).to have_received(:call).with(require_llm: true, require_tracing: false)
    expect(orchestrator).to have_received(:run).with(@tmpdir)
  end

  it "in --dry-run mode, classifies without building or calling an orchestrator" do
    File.write(File.join(@tmpdir, "chat.jsonl"), %({"name":"a","mes":"hi","send_date":"2026-01-01"}\n))
    boot_result = instance_double(
      SFL::Boot::Result, db: nil, llm_config: nil, chat_factory: nil, embedder: nil, classifier: nil,
      pass1_command: nil, pass1_env: nil, spacy_model: "en_core_web_sm", api_debug_errors: false, api_cors_origins: []
    )
    allow(SFL::Boot).to receive(:call).and_return(boot_result)
    allow(SFL::CLI).to receive(:build_ingest_orchestrator)

    SFL::CLI.run_ingest(@tmpdir, { output_dir: "./output/latest", dry_run: true, disable_tracing: true })

    expect(SFL::CLI).not_to have_received(:build_ingest_orchestrator)
  end
end
```

- [ ] **Step 3: Run the specs to verify they fail**

Run: `bundle exec rspec spec/cli/parse_spec.rb spec/cli/run_ingest_spec.rb`
Expected: FAIL — `ingest` not in the recognized subcommand list; `SFL::CLI.run_ingest`/`build_ingest_orchestrator` undefined

- [ ] **Step 4: Add the `ingest` subcommand to `USAGE` and `parse`**

Add a new line to the `Subcommands:` section of `USAGE` (`lib/sfl/cli.rb:43-54`), after the `context` line:

```
    ingest <path>                Classify and dispatch a file or directory of mixed
                                  input formats to the right analysis mode automatically
```

And a new `ingest:` section after `context:`'s option docs:

```
      ingest:
        --dry-run                     Classify without dispatching or writing review rows
```

Change (`lib/sfl/cli.rb:90`):

```ruby
      unless %i[conversation documentation knowledge_base context].include?(command)
```

to:

```ruby
      unless %i[conversation documentation knowledge_base context ingest].include?(command)
```

- [ ] **Step 5: Write `parse_ingest_options`**

Add after `parse_context_options` (`lib/sfl/cli.rb:176`):

```ruby
    module_function def parse_ingest_options(argv)
      options = { output_dir: DEFAULT_OUTPUT_DIR, dry_run: false }
      OptionParser.new do |opt|
        opt.on("--output-dir DIR") { |v| options[:output_dir] = v }
        opt.on("--dry-run") { options[:dry_run] = true }
        add_tracing_option(opt, options)
      end.parse!(argv)
      options
    end
```

- [ ] **Step 6: Write `run_ingest` and `build_ingest_orchestrator`**

Add after `run_context` (find its end via the method list already surveyed: `run_context` runs `:352-407` before `build_pipeline` at `:409`):

```ruby
    # Always require_llm: true (unlike conversation/documentation's --pass1-only escape
    # hatch) — classification is the whole point of this subcommand; there is no
    # deterministic-only mode for `ingest` the way --pass1-only skips Pass 2 elsewhere.
    module_function def run_ingest(input, options)
      boot_result = Boot.call(require_llm: true, require_tracing: !options[:disable_tracing])

      if options[:dry_run]
        run_ingest_dry_run(input, boot_result)
        return
      end

      orchestrator = build_ingest_orchestrator(boot_result, options)
      summary = orchestrator.run(input)
      puts "Ingest complete: #{summary[:dispatched]} dispatched, #{summary[:review_entries]} flagged for " \
        "review, #{summary[:drafted]} loader(s) drafted for review."
    end

    # --dry-run classifies every file and reports what *would* happen, without dispatching to
    # any engine or writing any ingest_review_entries row — a separate, simpler code path
    # rather than a flag threaded through Ingest::Orchestrator itself, so Orchestrator's own
    # contract stays side-effecting-by-default and easy to reason about.
    module_function def run_ingest_dry_run(input, boot_result)
      files = File.directory?(input) ? Dir.glob(File.join(input, "**", "*")).select { |p| File.file?(p) } : [input]
      files.each do |file|
        classification = Ingest::DeterministicRules.classify(file)
        classification ||= { format: "(would call classifier)", mode: nil }
        puts "#{file}: #{classification[:format]} / #{classification[:mode] || '?'}"
      end
    end

    module_function def build_ingest_orchestrator(boot_result, options)
      logger, instrumenter, breaker = build_collaborators
      pipeline = build_pipeline(boot_result, options.merge(pass1_only: false, store: false, resume: false),
        breaker:, instrumenter:, logger:)
      conversation_engine = Analysis::Engine.new(pipeline:)
      kb_source = Analysis::KnowledgeBaseSource.new(pipeline:)
      loader_drafter = Ingest::LoaderDrafter.new(chat: boot_result.chat_factory.for(:loader_drafting))
      review_repo = Store::PgIngestReviewRepository.new(boot_result.db)

      Ingest::Orchestrator.new(
        conversation_engine:, kb_source:, classifier: boot_result.classifier, loader_drafter:, review_repo:, logger:
      )
    end
```

- [ ] **Step 7: Run the specs to verify they pass**

Run: `bundle exec rspec spec/cli/parse_spec.rb spec/cli/run_ingest_spec.rb`
Expected: PASS

- [ ] **Step 8: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS, 0 failures (this is the first point every prior task's specs run together — confirms no cross-task regression, e.g. in `spec/boot/boot_spec.rb`'s existing examples after Task 7's `Result#classifier` addition)

- [ ] **Step 9: Rubocop the whole plan's changes**

Run: `bundle exec rubocop lib/sfl/cli.rb spec/cli/parse_spec.rb spec/cli/run_ingest_spec.rb`
Expected: no offenses

- [ ] **Step 10: Manual smoke test**

Run: `bundle exec exe/sfl-analyze ingest ./spec/fixtures --dry-run` (adjust to a real fixtures directory containing a mix of `.md`/`.jsonl` files if `spec/fixtures` doesn't exist at that exact path — confirm with `ls spec/fixtures` first)
Expected: one classification line printed per file, no errors, no DB writes (`--dry-run`)

- [ ] **Step 11: Commit**

```bash
git add lib/sfl/cli.rb spec/cli/parse_spec.rb spec/cli/run_ingest_spec.rb
git commit -m "feat(cli): add sfl-analyze ingest subcommand"
```

---

## Self-Review

**Spec coverage** — every component in the approved design doc has a task: `DeterministicRules` (5), `Core::Ports::Classifier`+adapters (4), `ClassificationResult` (3), `LoaderDrafter` (8), `ingest_review_entries`+`PgIngestReviewRepository` (1, 2), `Orchestrator` (9), model-tier task configs (7), CLI entry point (10). The design doc's worked data-flow example (unrecognized-format vs. ambiguous-mode branches) is directly covered by Task 9's spec cases. Deferred items (UI, `ingest review`/`resolve` subcommand) are called out in Global Constraints as explicitly out of scope, matching the design doc's Non-goals/Open Questions.

**Placeholder scan** — no TBD/TODO markers; every step has literal code, not a description of code. The one open design decision the spec left unresolved (confidence threshold, sample size) is resolved concretely in Task 9 (`CONFIDENCE_THRESHOLD = 0.6`, `SAMPLE_BYTES = 4096`) rather than left as a placeholder.

**Type/signature consistency** — `Core::Types::ClassificationResult` (Task 3: `format:, mode:, confidence:, reasoning:`) is constructed identically in Task 4's `Fake`/`Null` adapters, Task 6's `LLM::Classifier`, and consumed identically in Task 9's `Orchestrator#classify`. `Ingest::DeterministicRules.classify`'s `{format:, mode:, source_type:}` Hash shape (Task 5) matches exactly what Task 9's `#classify`/`#dispatch` read. `Store::PgIngestReviewRepository#enqueue`'s keyword names (Task 2) match every `review_repo.enqueue(...)` call site in Task 9. `Ingest::LoaderDrafter#draft`'s `{loader_path:, doc_path:}` return (Task 8) matches Task 9's `draft[:loader_path]`/`draft[:doc_path]` reads.

**One documented deviation from the approved spec:** Task 5 returns `source_type:` instead of the spec's sketched `loader_class:` key, because the three existing target engines already do their own internal loader dispatch — noted inline in Task 5 with rationale, doesn't change the architecture.
