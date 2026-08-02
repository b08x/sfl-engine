# Async Jobs (Piece 1 — shared with #29) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `sfl-api`'s fully-synchronous `POST /pipeline/compile` with an
async job (`202 {job_id}` + `GET /jobs/:id` polling), and add `POST /uploads`
(closing issue #29) on the same generic Postgres-backed job infrastructure —
no Gush, no Sidekiq, no Redis.

**Architecture:** Two new tables (`jobs`, `job_items`) hold durable job state.
A background `Thread` per item runs the exact synchronous work that already
exists today (`Core::Pipeline#compile` for compile, `Analysis::Engine#analyze`
for uploads), with an explicit `begin/rescue` writing `embedded`/`failed` to
the item row — Ruby swallows unhandled `Thread` exceptions silently, so this
rescue is load-bearing, not decorative. One job can have many items (one per
uploaded file); a raw ChatGPT/Claude export `.json` becomes one "export" item
whose children are the conversations it expands into (`parent_item_id`).
Item failures never flip the parent job to failed or block sibling items —
this is the same F11 partial-failure-isolation principle already used in
`lib/sfl/cli.rb`'s `run_conversation` and `PgEmbeddingStore#replace_document`.

**Tech Stack:** Ruby, Sequel (Postgres/pgvector), Rack (`rack-test` for specs),
`Dry::Monads::Result` (`Core::Pipeline#compile`'s return type), RSpec.

## Global Constraints

- No Gush, Sidekiq, or Redis. `redis` is not in the Gemfile and stays that
  way for this plan.
- No automatic crash-resume: if the API process dies mid-item, that item's
  row is orphaned at `processing` forever. Not handled here — deliberate
  scope cut per the spec.
- **Breaking API change**: `POST /pipeline/compile` currently returns
  `200 [AnnotatedClause, ...]` synchronously (`lib/sfl/api/server.rb:25`).
  After this plan it returns `202 {job_id:}`. No shipped consumer in this
  repo calls the HTTP API synchronously today (the CLI talks to
  `Core::Pipeline` directly, never over HTTP) — verified via
  `grep -rn "pipeline/compile" --include=*.rb` finding only `server.rb`
  and its spec. Safe to change now; would not be once a real client exists.
- F11 partial-failure isolation: one item's failure must never abort or
  block reporting on the rest of a job's items.
- `spec/support/store_test_db.rb`'s `.clean!` has a **hardcoded TRUNCATE
  list** (open issue #12: "will drift from db/migrations on new store
  tables"). Task 1 below adds `jobs`/`job_items` to that list explicitly —
  skipping this makes every subsequent spec in this plan flaky from
  cross-example row leakage, not just a missed cleanup.
- Every new Postgres table uses this codebase's existing convention:
  `String :id, primary_key: true` (app-generated UUID via
  `SecureRandom.uuid`), not a Postgres `serial`/`bigserial` — see
  `db/migrations/007_create_review_queue.rb`.
- Route handlers follow `lib/sfl/api/server.rb`'s existing shape: one
  private method per route, `ArgumentError` → `400` (handled centrally at
  `server.rb:86`, nothing new needed there), ad-hoc `raise "..."` on
  internal invariant violations → `500` with a logged `request_id`
  (`server.rb:88-94`).

---

### Task 1: `jobs`/`job_items` migration

**Files:**
- Create: `db/migrations/009_create_jobs.rb`
- Modify: `spec/support/store_test_db.rb` (TRUNCATE list)

**Interfaces:**
- Produces: `jobs` table (`id, kind, status, payload jsonb, created_at,
  updated_at`), `job_items` table (`id, job_id, parent_item_id, label,
  kind, status, clause_count, result jsonb, error, created_at,
  updated_at`). Every later task in this plan reads/writes these two
  tables only through `Store::PgJobRepository` (Task 2) — no other task
  touches `db[:jobs]`/`db[:job_items]` directly.

- [ ] **Step 1: Write the migration**

```ruby
# frozen_string_literal: true

# Generic async-job infrastructure (docs/superpowers/specs/
# 2026-08-02-async-compile-and-provider-backup-design.md, Piece 1):
# shared by POST /pipeline/compile (one job, one item) and POST /uploads
# (#29 — one job, one item per uploaded file, export files' items gaining
# child items via parent_item_id once expanded). `jobs.status` only
# tracks whether every item has reached a terminal state
# (embedded|failed); per-item outcomes, including failures, live on
# job_items — F11 partial-failure isolation, so one item's failure never
# flips the parent job to a blanket "failed" or blocks the rest.
Sequel.migration do
  change do
    create_table(:jobs) do
      String :id, primary_key: true # UUID
      String :kind, null: false # "pipeline_compile" | "upload"
      String :status, null: false, default: "processing" # "processing" | "done"
      column :payload, :jsonb, default: "{}"
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :status, name: :idx_jobs_status
    end

    create_table(:job_items) do
      String :id, primary_key: true # UUID
      foreign_key :job_id, :jobs, type: String, null: false
      foreign_key :parent_item_id, :job_items, type: String # set for an
        # export's expanded conversation children; nil for everything else
      String :label, null: false
      String :kind, null: false # "compile" | "conversation_file" | "export" | "conversation"
      String :status, null: false, default: "queued" # "queued"|"processing"|"embedded"|"failed"
      Integer :clause_count
      column :result, :jsonb
      String :error, text: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :job_id, name: :idx_job_items_job_id
      index :parent_item_id, name: :idx_job_items_parent_item_id
      index :status, name: :idx_job_items_status
    end
  end
end
```

- [ ] **Step 2: Run the migration against the test database**

Run: `DATABASE_URL_V2_TEST=postgresql://sfl:sfl@localhost:5433/sfl_engine_v2_test bundle exec rake db:migrate` — or simply run any store spec (`StoreTestDb.db` runs `Sequel::Migrator.run` automatically, see `spec/support/store_test_db.rb:34`).

Expected: no migration errors; `db/migrations/009_create_jobs.rb` is the new head migration.

- [ ] **Step 3: Add the new tables to `StoreTestDb.clean!`'s TRUNCATE list**

In `spec/support/store_test_db.rb`, change:

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
                   annotation_reviews, review_queue, jobs, job_items
          RESTART IDENTITY CASCADE
        SQL
      end
```

- [ ] **Step 4: Commit**

```bash
git add db/migrations/009_create_jobs.rb spec/support/store_test_db.rb
git commit -m "feat(store): add jobs/job_items tables for async pipeline/upload jobs"
```

---

### Task 2: `SFL::Store::PgJobRepository`

**Files:**
- Create: `lib/sfl/store/pg_job_repository.rb`
- Test: `spec/store/pg_job_repository_spec.rb`

**Interfaces:**
- Consumes: `Sequel::Database` (`db`, injected — same pattern as
  `PgReviewQueueRepository.new(db)`).
- Produces (used by Task 4/5/6):
  - `create_job(kind:, payload: {}) -> String` (job id)
  - `add_item(job_id:, label:, kind:, parent_item_id: nil) -> String` (item id)
  - `mark_item_processing(item_id) -> void`
  - `complete_item(item_id, result:, clause_count: nil) -> void` — sets
    status `"embedded"`, then marks the parent job `"done"` if every item
    on that job is now terminal.
  - `fail_item(item_id, error:) -> void` — sets status `"failed"`, same
    job-completion check as `complete_item`.
  - `find(job_id) -> Hash, nil` — `{id:, kind:, status:, items:
    [{id:, label:, kind:, status:, clause_count:, error:, result:,
    children: [...]}]}`, `children` populated from rows whose
    `parent_item_id` equals this item's `id`; top-level `items` excludes
    rows that are someone else's child. `nil` if the job doesn't exist.

- [ ] **Step 1: Write the failing spec**

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Store::PgJobRepository do
  subject(:repo) { described_class.new(db) }

  let(:db) { SFL::Store::StoreTestDb.db }

  before { SFL::Store::StoreTestDb.clean! }

  describe "#create_job and #add_item" do
    it "creates a job and attaches items to it" do
      job_id = repo.create_job(kind: "upload", payload: { filenames: ["a.jsonl"] })
      item_id = repo.add_item(job_id:, label: "a.jsonl", kind: "conversation_file")

      job_row = db[:jobs].where(id: job_id).first
      item_row = db[:job_items].where(id: item_id).first

      expect(job_row).to include(kind: "upload", status: "processing")
      expect(item_row).to include(job_id:, label: "a.jsonl", kind: "conversation_file", status: "queued")
    end

    it "supports a parent_item_id for export-expansion children" do
      job_id = repo.create_job(kind: "upload")
      parent_id = repo.add_item(job_id:, label: "export.json", kind: "export")
      child_id = repo.add_item(job_id:, label: "conv-1", kind: "conversation", parent_item_id: parent_id)

      child_row = db[:job_items].where(id: child_id).first
      expect(child_row[:parent_item_id]).to eq(parent_id)
    end
  end

  describe "#mark_item_processing" do
    it "sets the item's status to processing" do
      job_id = repo.create_job(kind: "pipeline_compile")
      item_id = repo.add_item(job_id:, label: "doc-1", kind: "compile")

      repo.mark_item_processing(item_id)

      expect(db[:job_items].where(id: item_id).first[:status]).to eq("processing")
    end
  end

  describe "#complete_item" do
    it "marks the item embedded with its result and clause_count" do
      job_id = repo.create_job(kind: "pipeline_compile")
      item_id = repo.add_item(job_id:, label: "doc-1", kind: "compile")

      repo.complete_item(item_id, result: { clauses: [] }, clause_count: 0)

      row = db[:job_items].where(id: item_id).first
      expect(row[:status]).to eq("embedded")
      expect(row[:clause_count]).to eq(0)
      expect(JSON.parse(row[:result])).to eq({ "clauses" => [] })
    end

    it "marks the parent job done once every item is terminal" do
      job_id = repo.create_job(kind: "upload")
      item_a = repo.add_item(job_id:, label: "a", kind: "conversation_file")
      item_b = repo.add_item(job_id:, label: "b", kind: "conversation_file")

      repo.complete_item(item_a, result: {})
      expect(db[:jobs].where(id: job_id).first[:status]).to eq("processing"), "job_b still queued"

      repo.complete_item(item_b, result: {})
      expect(db[:jobs].where(id: job_id).first[:status]).to eq("done")
    end
  end

  describe "#fail_item" do
    it "marks the item failed with an error message, without touching sibling items" do
      job_id = repo.create_job(kind: "upload")
      failing = repo.add_item(job_id:, label: "bad.jsonl", kind: "conversation_file")
      ok = repo.add_item(job_id:, label: "good.jsonl", kind: "conversation_file")

      repo.fail_item(failing, error: "malformed JSON")
      repo.complete_item(ok, result: {})

      failing_row = db[:job_items].where(id: failing).first
      ok_row = db[:job_items].where(id: ok).first
      expect(failing_row).to include(status: "failed", error: "malformed JSON")
      expect(ok_row[:status]).to eq("embedded")
      expect(db[:jobs].where(id: job_id).first[:status]).to eq("done")
    end
  end

  describe "#find" do
    it "returns nil for an unknown job id" do
      expect(repo.find("nonexistent")).to be_nil
    end

    it "nests children under their parent item and excludes them from the top-level list" do
      job_id = repo.create_job(kind: "upload")
      parent_id = repo.add_item(job_id:, label: "export.json", kind: "export")
      child_id = repo.add_item(job_id:, label: "conv-1", kind: "conversation", parent_item_id: parent_id)
      repo.complete_item(parent_id, result: { expanded_count: 1 })
      repo.complete_item(child_id, result: { clauses: [] }, clause_count: 0)

      found = repo.find(job_id)

      expect(found[:status]).to eq("done")
      expect(found[:items].map { |i| i[:id] }).to eq([parent_id])
      expect(found[:items].first[:children].map { |c| c[:id] }).to eq([child_id])
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/store/pg_job_repository_spec.rb`
Expected: `NameError: uninitialized constant SFL::Store::PgJobRepository`

- [ ] **Step 3: Write the implementation**

```ruby
# frozen_string_literal: true

require "sequel"
require "securerandom"
require "json"

module SFL
  module Store
    # Generic async-job infrastructure (docs/superpowers/specs/
    # 2026-08-02-async-compile-and-provider-backup-design.md, Piece 1):
    # backs both POST /pipeline/compile (one job, one item) and POST
    # /uploads (#29 — one item per file, export items gaining
    # parent_item_id-linked children once expanded). `jobs.status` only
    # tracks whether every item has reached a terminal state; per-item
    # outcomes, including failures, live on job_items so one item's
    # failure never blocks or hides the rest (F11).
    class PgJobRepository
      TERMINAL_STATUSES = %w[embedded failed].freeze

      # @param db [Sequel::Database]
      def initialize(db)
        @db = db
      end

      # @param kind [String] "pipeline_compile" | "upload"
      # @param payload [Hash] the original request's params, for observability
      # @return [String] the new job's id
      def create_job(kind:, payload: {})
        id = SecureRandom.uuid
        @db[:jobs].insert(id:, kind:, status: "processing", payload: JSON.dump(payload), created_at: Time.now,
          updated_at: Time.now)
        id
      end

      # @param job_id [String]
      # @param label [String]
      # @param kind [String] "compile" | "conversation_file" | "export" | "conversation"
      # @param parent_item_id [String, nil] set for an export's expanded conversation children
      # @return [String] the new item's id
      def add_item(job_id:, label:, kind:, parent_item_id: nil)
        id = SecureRandom.uuid
        @db[:job_items].insert(
          id:, job_id:, parent_item_id:, label:, kind:, status: "queued",
          created_at: Time.now, updated_at: Time.now
        )
        id
      end

      # @param item_id [String]
      # @return [void]
      def mark_item_processing(item_id)
        @db[:job_items].where(id: item_id).update(status: "processing", updated_at: Time.now)
      end

      # @param item_id [String]
      # @param result [Hash] JSON-serializable
      # @param clause_count [Integer, nil]
      # @return [void]
      def complete_item(item_id, result:, clause_count: nil)
        @db[:job_items].where(id: item_id).update(
          status: "embedded", result: JSON.dump(result), clause_count:, updated_at: Time.now
        )
        maybe_complete_job(job_id_for(item_id))
      end

      # @param item_id [String]
      # @param error [String]
      # @return [void]
      def fail_item(item_id, error:)
        @db[:job_items].where(id: item_id).update(status: "failed", error:, updated_at: Time.now)
        maybe_complete_job(job_id_for(item_id))
      end

      # @param job_id [String]
      # @return [Hash, nil]
      def find(job_id)
        job_row = @db[:jobs].where(id: job_id).first
        return nil unless job_row

        items = @db[:job_items].where(job_id:).all
        top_level = items.reject { |i| i[:parent_item_id] }

        {
          id: job_row[:id], kind: job_row[:kind], status: job_row[:status],
          items: top_level.map { |i| item_hash(i, items) },
        }
      end

      private def item_hash(item, all_items)
        {
          id: item[:id], label: item[:label], kind: item[:kind], status: item[:status],
          clause_count: item[:clause_count], error: item[:error],
          result: item[:result] && JSON.parse(item[:result]),
          children: all_items.select { |i| i[:parent_item_id] == item[:id] }.map { |c| item_hash(c, all_items) },
        }
      end

      private def job_id_for(item_id)
        @db[:job_items].where(id: item_id).get(:job_id)
      end

      private def maybe_complete_job(job_id)
        return if @db[:job_items].where(job_id:).exclude(status: TERMINAL_STATUSES).any?

        @db[:jobs].where(id: job_id).update(status: "done", updated_at: Time.now)
      end
    end
  end
end
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/store/pg_job_repository_spec.rb`
Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add lib/sfl/store/pg_job_repository.rb spec/store/pg_job_repository_spec.rb
git commit -m "feat(store): add PgJobRepository for async job/item tracking"
```

---

### Task 3: Wire `job_repo` (and a conversation engine) into `API::Context`

**Files:**
- Modify: `lib/sfl/api/context.rb`
- Modify: `spec/api/context_spec.rb`

**Interfaces:**
- Consumes: `Store::PgJobRepository` (Task 2), `Analysis::Engine` (existing
  class, `lib/sfl/analysis/engine.rb`).
- Produces: `ctx.job_repo` (`Store::PgJobRepository`), `ctx.conversation_engine`
  (`Analysis::Engine`, built with no `on_progress`/`on_turn_start` — those
  default to `nil` per `engine.rb:52-53`, and there's no terminal to draw a
  progress bar to over HTTP) — both consumed by Task 4/5/6.

- [ ] **Step 1: Extend the failing assertion in the existing Context spec**

In `spec/api/context_spec.rb`, add to the existing `it "wires a
fully-populated Context..."` example, right after the `expect(ctx.clause_review_service)...` line:

```ruby
      expect(ctx.job_repo).to be_a(SFL::Store::PgJobRepository)
      expect(ctx.conversation_engine).to be_a(SFL::Analysis::Engine)
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/api/context_spec.rb`
Expected: `NoMethodError: undefined method 'job_repo' for #<struct SFL::API::Context ...>`

- [ ] **Step 3: Add the fields and wiring**

In `lib/sfl/api/context.rb`, change the `Struct.new` call:

```ruby
    Context = Struct.new(
      :pipeline, :retriever, :synthesizer, :clause_store, :review_queue_repo,
      :annotation_review_repo, :pass_two, :clause_review_service, :job_repo, :conversation_engine,
      keyword_init: true
    )
```

and in `self.build`, add before the final `new(...)` call:

```ruby
        job_repo = Store::PgJobRepository.new(boot_result.db)
        conversation_engine = Analysis::Engine.new(pipeline:, review_queue_repo: Store::PgReviewQueueRepository.new(boot_result.db))
```

then add `job_repo:` and `conversation_engine:` as two more keyword args to
that `new(...)` call, alongside the existing `pipeline:`, `retriever:`, etc.

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/api/context_spec.rb`
Expected: passes.

- [ ] **Step 5: Commit**

```bash
git add lib/sfl/api/context.rb spec/api/context_spec.rb
git commit -m "feat(api): wire PgJobRepository and a conversation Analysis::Engine into Context"
```

---

### Task 4: Async `POST /pipeline/compile` + `GET /jobs/:id`

**Files:**
- Modify: `lib/sfl/api/server.rb`
- Modify: `spec/api/server_spec.rb`

**Interfaces:**
- Consumes: `ctx.job_repo` (Task 2/3), `ctx.pipeline.compile(text,
  document_id:, store:, embed:, resume:)` (existing, returns
  `Dry::Monads::Result`).
- Produces: `POST /pipeline/compile` → `202 {job_id:}`; `GET /jobs/:id` →
  `200 {id:, kind:, status:, items:}` or `404 {error:}`. A private
  `run_job_item_async(item_id) { block }` helper, reused by Task 5/6 for
  the same explicit-`begin/rescue`-in-a-`Thread` pattern.

- [ ] **Step 1: Write the failing specs**

Replace the existing `describe "POST /pipeline/compile"` block in
`spec/api/server_spec.rb` (currently asserting a synchronous `200`
response — that behavior no longer exists after this task) with:

```ruby
  describe "POST /pipeline/compile" do
    it "returns 400 when text is missing" do
      post "/pipeline/compile", JSON.dump({}), "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(400)
    end

    it "returns 202 with a job_id before the background compile finishes, and GET /jobs/:id " \
      "reports processing/queued while it's still in flight" do
      gate = Queue.new
      allow(pipeline).to receive(:compile) do
        gate.pop # blocks until the test releases it, proving the response didn't wait
        Success([build_clause])
      end

      post "/pipeline/compile", JSON.dump({ text: "hello", document_id: "doc-1" }),
        "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(202)
      job_id = JSON.parse(last_response.body)["job_id"]
      expect(job_id).to be_a(String)

      get "/jobs/#{job_id}"
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("processing")
      expect(body["items"].first["status"]).to eq("processing")

      gate << :go # let the background thread proceed so it doesn't leak into later examples
      sleep 0.05
    end

    it "records the compiled clauses on the job once the background thread finishes" do
      allow(pipeline).to receive(:compile).and_return(Success([build_clause]))

      post "/pipeline/compile", JSON.dump({ text: "hello", document_id: "doc-1" }),
        "CONTENT_TYPE" => "application/json"
      job_id = JSON.parse(last_response.body)["job_id"]
      sleep 0.05 # background thread is effectively instant against a stubbed pipeline

      get "/jobs/#{job_id}"

      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("done")
      expect(body["items"].first["status"]).to eq("embedded")
      expect(body["items"].first["clause_count"]).to eq(1)
    end

    it "records the failure on the job when the pipeline raises" do
      allow(pipeline).to receive(:compile).and_return(Failure("boom"))

      post "/pipeline/compile", JSON.dump({ text: "hello", document_id: "doc-1" }),
        "CONTENT_TYPE" => "application/json"
      job_id = JSON.parse(last_response.body)["job_id"]
      sleep 0.05

      get "/jobs/#{job_id}"

      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("done")
      expect(body["items"].first["status"]).to eq("failed")
      expect(body["items"].first["error"]).to include("boom")
    end
  end

  describe "GET /jobs/:id" do
    it "returns 404 for an unknown job id" do
      get "/jobs/nonexistent"
      expect(last_response.status).to eq(404)
    end
  end
```

Add `let(:job_repo) { instance_double(SFL::Store::PgJobRepository) }` to the
top-level `let` block, add `job_repo:` to the `ctx` construction, and add
`require "securerandom"` is already present via `server.rb`'s own require —
no new spec-file require needed. Because these specs use a **real**
`PgJobRepository`-shaped double is impractical here (the job actually needs
to persist across the `POST` and the following `GET` within one example),
replace the `job_repo` double with a real one backed by the test database:

```ruby
  let(:job_repo) { SFL::Store::PgJobRepository.new(SFL::Store::StoreTestDb.db) }

  before { SFL::Store::StoreTestDb.clean! }
```

(This mirrors `spec/api/clause_review_service_spec.rb`'s existing pattern of
mixing doubles for stateless collaborators with a real, DB-backed
collaborator for the one piece of state a test genuinely needs to observe
change over time — confirm that file's exact convention before writing this
if it differs.)

- [ ] **Step 2: Run the specs to verify they fail**

Run: `bundle exec rspec spec/api/server_spec.rb -e "POST /pipeline/compile" -e "GET /jobs/:id"`
Expected: failures — `compile_pipeline` still returns `200` synchronously, `GET /jobs/:id` route doesn't exist (`404 Not Found` from the catch-all, but with the old response shape / no route matched).

- [ ] **Step 3: Implement the route changes**

In `lib/sfl/api/server.rb`, add to the `Routes:` comment block:

```
    #   GET  /jobs/:id                  -> {id:, kind:, status:, items:[...]}
```

Add to the `dispatch` `case` statement, alongside the existing routes:

```ruby
        in ["GET", JOB_RE]
          show_job(req.path_info.match(JOB_RE)[1])
```

Add the new route regex next to the other `_RE` constants:

```ruby
      JOB_RE = %r{\A/jobs/([^/]+)\z}
```

Replace the existing `compile_pipeline` method body:

```ruby
      # POST /pipeline/compile
      #
      # Body: {text:, document_id:, store:, embed:}
      # Async since #29/track-decision-async-jobs: returns 202 immediately,
      # the actual compile runs on a background Thread. GET /jobs/:id polls
      # for the result. rubocop:disable Metrics/AbcSize -- one flat
      # validate/create-job/spawn/respond sequence.
      private def compile_pipeline(req)
        body = parse_body(req)
        text = body["text"]
        raise ArgumentError, "text is required" if text.nil? || text.to_s.strip.empty?

        document_id = body["document_id"] || "api-#{SecureRandom.uuid}"
        store = body.fetch("store", false)
        embed = body.fetch("embed", false)

        job_id = ctx.job_repo.create_job(kind: "pipeline_compile", payload: { document_id:, store:, embed: })
        item_id = ctx.job_repo.add_item(job_id:, label: document_id, kind: "compile")

        run_job_item_async(item_id) do
          clauses = ctx.pipeline.compile(text, document_id:, store:, embed:, resume: false)
            .value_or { |failure| raise "compile failed for #{document_id.inspect}: #{failure.inspect}" }
          { result: { clauses: clauses.map { |c| Core::Wire.dump(c) } }, clause_count: clauses.size }
        end

        json(202, { job_id: })
      end
      # rubocop:enable Metrics/AbcSize
```

Add the new `show_job` route method and the shared background-thread helper,
placed near `compile_pipeline`:

```ruby
      # GET /jobs/:id
      private def show_job(id)
        job = ctx.job_repo.find(id)
        return json(404, { error: "job not found", id: }) unless job

        json(200, job)
      end

      # Runs `block` on a background Thread, marking `item_id` processing
      # first and embedded/failed on completion. The begin/rescue inside
      # the Thread body is load-bearing: Ruby silently swallows an
      # unhandled exception in a bare Thread (it never surfaces without
      # Thread#join or abort_on_exception), and abort_on_exception would
      # crash the whole API process rather than just failing this one
      # item. `block` must return `{result:, clause_count:}`.
      private def run_job_item_async(item_id, &block)
        ctx.job_repo.mark_item_processing(item_id)
        Thread.new do
          outcome = block.call
          ctx.job_repo.complete_item(item_id, result: outcome[:result], clause_count: outcome[:clause_count])
        rescue => e
          ctx.job_repo.fail_item(item_id, error: e.message)
        end
      end
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `bundle exec rspec spec/api/server_spec.rb`
Expected: all examples pass, including every other pre-existing route's specs (unaffected by this change).

- [ ] **Step 5: Commit**

```bash
git add lib/sfl/api/server.rb spec/api/server_spec.rb
git commit -m "feat(api): make POST /pipeline/compile async, add GET /jobs/:id"
```

---

### Task 5: `POST /uploads` — file receipt, native + export-expansion item creation

**Files:**
- Modify: `lib/sfl/api/server.rb`
- Modify: `spec/api/server_spec.rb`

**Interfaces:**
- Consumes: `Analysis::ChatExportExpander.detect_format(path)` /
  `.expand(path, dest_dir:)` (existing, `lib/sfl/analysis/chat_export_expander.rb`),
  `ctx.job_repo` (Task 2/3).
- Produces: `POST /uploads` → `202 {job_id:}`. Every `job_items` row for
  this job — including expanded children — exists in the database
  **before** the response is sent and before Task 6's background threads
  are spawned; this ordering is what makes the job-completion check in
  `PgJobRepository#maybe_complete_job` (Task 2) race-free.

- [ ] **Step 1: Write the failing specs**

Add to `spec/api/server_spec.rb`:

```ruby
  describe "POST /uploads" do
    def upload_file(name, content)
      Rack::Test::UploadedFile.new(StringIO.new(content), "application/octet-stream", true, original_filename: name)
    end

    it "returns 202 with a job_id and creates one item per native conversation file" do
      allow(conversation_engine).to receive(:analyze) # stubbed synchronously below in Task 6's specs

      post "/uploads", "files[]" => upload_file("a.jsonl", '{"name":"u","mes":"hi","send_date":null}')

      expect(last_response.status).to eq(202)
      job_id = JSON.parse(last_response.body)["job_id"]
      sleep 0.05

      get "/jobs/#{job_id}"
      items = JSON.parse(last_response.body)["items"]
      expect(items.map { |i| i["label"] }).to eq(["a.jsonl"])
      expect(items.first["kind"]).to eq("conversation_file")
    end

    it "returns 400 when no files are provided" do
      post "/uploads", {}
      expect(last_response.status).to eq(400)
    end

    it "returns 202 before the background analyze finishes" do
      gate = Queue.new
      allow(conversation_engine).to receive(:analyze) { gate.pop }

      post "/uploads", "files[]" => upload_file("a.jsonl", '{"name":"u","mes":"hi","send_date":null}')

      expect(last_response.status).to eq(202)
      job_id = JSON.parse(last_response.body)["job_id"]

      get "/jobs/#{job_id}"
      expect(JSON.parse(last_response.body)["items"].first["status"]).to eq("processing")

      gate << instance_double(SFL::Core::Types::AnalysisResult, turns: [])
      sleep 0.05
    end

    it "expands a raw ChatGPT export into a parent export item with one child item per conversation" do
      export_json = JSON.dump([
        { "title" => "Conv One", "mapping" => {
          "1" => { "message" => { "author" => { "role" => "user" }, "content" => { "parts" => ["hi"] },
                                   "create_time" => 1_700_000_000 }, "parent" => nil, "children" => [] },
        } },
      ])
      allow(conversation_engine).to receive(:analyze)

      post "/uploads", "files[]" => upload_file("export.json", export_json)

      job_id = JSON.parse(last_response.body)["job_id"]
      sleep 0.05

      get "/jobs/#{job_id}"
      items = JSON.parse(last_response.body)["items"]
      expect(items.first["kind"]).to eq("export")
      expect(items.first["children"].size).to eq(1)
      expect(items.first["children"].first["kind"]).to eq("conversation")
    end

    it "isolates one file's expansion failure from the rest (F11)" do
      allow(conversation_engine).to receive(:analyze)

      post "/uploads",
        "files[]" => [upload_file("bad.json", "not valid json"), upload_file("good.jsonl", '{"name":"u","mes":"hi","send_date":null}')]

      job_id = JSON.parse(last_response.body)["job_id"]
      sleep 0.05

      get "/jobs/#{job_id}"
      items = JSON.parse(last_response.body)["items"]
      bad = items.find { |i| i["label"] == "bad.json" }
      good = items.find { |i| i["label"] == "good.jsonl" }
      expect(bad["status"]).to eq("failed")
      expect(good).not_to be_nil
    end
  end
```

Add `let(:conversation_engine) { instance_double(SFL::Analysis::Engine) }` to
the top-level `let` block and `conversation_engine:` to the `ctx`
construction.

- [ ] **Step 2: Run the specs to verify they fail**

Run: `bundle exec rspec spec/api/server_spec.rb -e "POST /uploads"`
Expected: `404 Not Found` — the route doesn't exist yet.

- [ ] **Step 3: Implement `POST /uploads`**

Add to the `Routes:` comment block:

```
    #   POST /uploads                  -> {job_id:} (async, #29)
```

Add to `dispatch`:

```ruby
        in ["POST", "/uploads"]
          create_upload(req)
```

Add the constants used for classifying uploaded files, next to the other
`_RE`/filter constants:

```ruby
      NATIVE_CONVERSATION_EXTENSIONS = %w[.jsonl .srt .vtt .ass].freeze
```

Add the route implementation, near `compile_pipeline`:

```ruby
      # POST /uploads (#29)
      #
      # multipart/form-data, one or more `files[]` parts. Native
      # .jsonl/.srt/.vtt/.ass files each become one "conversation_file"
      # item. Raw ChatGPT/Claude export .json files become one "export"
      # item plus one "conversation" child item per conversation the
      # export expands into (Analysis::ChatExportExpander) — an
      # individual file's expansion failure is recorded on that file's
      # own item and never blocks the rest (F11). Every item, including
      # expanded children, exists in the DB before any background thread
      # is spawned (Task 6) and before this responds — see
      # PgJobRepository#maybe_complete_job's race-freedom note.
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- one flat
      # validate/save-uploads/classify/expand/create-items/spawn/respond
      # sequence; each line is a distinct step already named by a comment,
      # not something with a natural sub-method boundary.
      private def create_upload(req)
        uploads = Array(req.params["files"])
        raise ArgumentError, "at least one file is required" if uploads.empty?

        tmp_dir = Dir.mktmpdir("sfl-upload")
        job_id = ctx.job_repo.create_job(kind: "upload", payload: { filenames: uploads.map { |f| f[:filename] } })

        items = uploads.flat_map { |upload| create_items_for_upload(job_id, upload, tmp_dir) }
        items.each { |item_id, path, source_type| run_upload_item_async(item_id, path, source_type) }

        json(202, { job_id: })
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      private def create_items_for_upload(job_id, upload, tmp_dir)
        filename = upload[:filename]
        # File.basename strips any directory components the client-supplied
        # filename might contain (Content-Disposition's filename is fully
        # attacker-controlled) — without it, a filename like
        # "../../../../etc/cron.d/evil" would let File.join write outside
        # tmp_dir entirely (Ruby's File.join does not collapse ".." segments).
        saved_path = File.join(tmp_dir, File.basename(filename))
        File.binwrite(saved_path, upload[:tempfile].read)

        if File.extname(filename).casecmp(".json").zero?
          create_export_items(job_id, filename, saved_path, tmp_dir)
        else
          item_id = ctx.job_repo.add_item(job_id:, label: filename, kind: "conversation_file")
          [[item_id, saved_path, "chat_native"]]
        end
      end

      private def create_export_items(job_id, filename, saved_path, tmp_dir)
        export_item_id = ctx.job_repo.add_item(job_id:, label: filename, kind: "export")
        expanded = Analysis::ChatExportExpander.expand(saved_path, dest_dir: File.join(tmp_dir, "_expanded"))
        ctx.job_repo.complete_item(export_item_id, result: { expanded_count: expanded.size })

        expanded.map do |entry|
          child_id = ctx.job_repo.add_item(
            job_id:, label: entry[:label], kind: "conversation", parent_item_id: export_item_id
          )
          [child_id, entry[:path], entry[:source_type]]
        end
      rescue Core::Loaders::Error => e
        ctx.job_repo.fail_item(export_item_id, error: e.message)
        []
      end
```

`require "tmpdir"` needs adding to `server.rb`'s existing `require` block at
the top of the file (alongside `require "json"`, `require "rack"`, etc.).

- [ ] **Step 4: Run the specs to verify they fail for the right reason**

Run: `bundle exec rspec spec/api/server_spec.rb -e "POST /uploads"`
Expected: still failing, but now on `run_upload_item_async` being
undefined — that's Task 6's job. Confirms Task 5's own responsibility
(item creation, expansion, F11 isolation on expansion failure) is
otherwise wired correctly.

- [ ] **Step 5: Commit**

```bash
git add lib/sfl/api/server.rb spec/api/server_spec.rb
git commit -m "feat(api): add POST /uploads item/expansion creation (background processing in next commit)"
```

---

### Task 6: Background processing for upload items

**Files:**
- Modify: `lib/sfl/api/server.rb`

**Interfaces:**
- Consumes: `ctx.conversation_engine.analyze(source, label:, store:,
  resume:)` (Task 3, existing `Analysis::Engine#analyze` signature at
  `lib/sfl/analysis/engine.rb:76`), `Analysis::ConversationSource.new(path,
  source_type:)` (existing).
- Produces: `run_upload_item_async(item_id, path, source_type)` — the
  Task 5 call site this task makes real.

- [ ] **Step 1: Run Task 5's specs to confirm they now fail only on the missing method**

Run: `bundle exec rspec spec/api/server_spec.rb -e "POST /uploads"`
Expected: `NoMethodError: undefined method 'run_upload_item_async'`.

- [ ] **Step 2: Implement the method**

Add next to `run_job_item_async`:

```ruby
      # Background processing for one uploaded conversation file or
      # expanded-export child. Reuses the exact Analysis::Engine#analyze
      # call CLI.process_conversation_file makes for `sfl-analyze
      # conversation` (lib/sfl/cli.rb:247-259), so an uploaded file and a
      # CLI-analyzed file produce the same result shape.
      private def run_upload_item_async(item_id, path, source_type)
        run_job_item_async(item_id) do
          source = Analysis::ConversationSource.new(path, source_type:)
          result = ctx.conversation_engine.analyze(source, label: File.basename(path, ".*"), store: true, resume: false)
          clause_count = result.turns.sum { |t| t.clauses.size }
          { result: Core::Wire.dump(result), clause_count: }
        end
      end
```

- [ ] **Step 3: Run all the upload specs to verify they pass**

Run: `bundle exec rspec spec/api/server_spec.rb -e "POST /uploads"`
Expected: all pass, including the F11 isolation example (`bad.json`
fails at expansion, `good.jsonl` still completes independently).

- [ ] **Step 4: Run the full server + repository spec files**

Run: `bundle exec rspec spec/api/server_spec.rb spec/api/context_spec.rb spec/store/pg_job_repository_spec.rb`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/sfl/api/server.rb
git commit -m "feat(api): run uploaded conversation files through Analysis::Engine in the background"
```

---

### Task 7: Full-suite regression check

**Files:** none (verification-only task).

- [ ] **Step 1: Run the entire test suite**

Run: `bundle exec rspec`
Expected: no failures anywhere outside this plan's own new/modified specs
— in particular, confirm no other spec was relying on `POST
/pipeline/compile`'s old synchronous `200` response shape (the Global
Constraints section's breaking-change note already checked this via
`grep`, but a full suite run is the actual proof).

- [ ] **Step 2: Run Rubocop over the changed files**

Run: `bundle exec rubocop lib/sfl/store/pg_job_repository.rb lib/sfl/api/context.rb lib/sfl/api/server.rb db/migrations/009_create_jobs.rb`
Expected: no offenses (or only the `Metrics/AbcSize`/`Metrics/MethodLength`
disables this plan already wrote inline, matching this file's existing
disable-with-rationale convention).

- [ ] **Step 3: Commit if Rubocop required any fixes**

```bash
git add -u
git commit -m "chore: rubocop fixes for async jobs work"
```
