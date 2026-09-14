# Code-insights Telemetry Ingest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ingest AI coding session telemetry from `~/.code-insights/data.db` into sfl-engine as three registers under a shared session parent, with a computed, explainable grounding score on every insight.

**Architecture:** One read-only SQLite origin (`Store::CodeInsightsSource`) yields `RowRef`s across three scopes. Scopes route to `:conversation`, `:analytic`, and `:tool_trace` registers. `Core::Types::Unit` is not reopened; typed `Dry::Struct` payloads validate the differing schemas and ride in `metadata["payload"]`. Ingest defers embeddings; a later rake pass scores grounding and rewrites `untrusted`/`modality_weight`.

**Tech Stack:** Ruby, Sequel, `sqlite3` gem, Dry::Struct / Dry::Types, RSpec, Zeitwerk, `SFL::LLM::Embedder` (Ollama `/api/embed`, `embeddinggemma:latest`, 768d), `Core::Ports::Instrumenter` → Langfuse via `dspy/o11y/langfuse`.

**Spec:** `docs/superpowers/specs/2026-09-14-code-insights-telemetry-ingest-design.md`

## Global Constraints

- `Core::Types::Unit` is a closed `Dry::Struct` with exactly seven attributes: `document_id`, `text`, `heading`, `speaker`, `is_user`, `sent_at`, `metadata`. **Do not add attributes to it.** Structured data goes in `metadata`, per `json_source.rb:79` and `csv_source.rb:62`.
- The telemetry DB at `~/.code-insights/data.db` is opened **read-only**, always. Never write to it.
- Embedding model is `embeddinggemma:latest` at 768 dimensions. Rows embedded at any other dimension are excluded (expected: 6 rows using `qwen3-embedding:0.6b` at 1024).
- Every loader is a `Core::Loaders::Source` (`#each_unit` yielding `Core::Types::Unit`, `NotImplementedError` convention, `Enumerator` when no block given).
- Ports get `Null::` and `Fake::` doubles, matching `lib/sfl/core/ports/null/` and `lib/sfl/core/ports/fake/`.
- `frozen_string_literal: true` on every new file. Zeitwerk naming; `rake zeitwerk:check` is in the default task.
- Run `bundle exec rspec <path>` for single specs, `bundle exec rake` for the full gate (spec + rubocop + zeitwerk:check).
- Grounding weights `w1`/`w2`/`w3` and threshold `tau` are **configuration, never constants in code**.

---

## Board integration

This plan adds five cards and amends two that already exist in the `Ingest/Parser Hexagon Refactor` track. **Task 0 is card surgery, not code.** Do it first; the amendments change acceptance criteria on cards that have not been built, which is the cheap moment to change them.

| Card | Action |
|---|---|
| `[SFL-ING-16] Core::Ports::CorpusSource and the FileRef contract` | Amend: widen `FileRef` to a `Ref` contract |
| `[SFL-ING-22] Core::Ports::RegisterProfile and the register catalog` | Amend: five new acceptance criteria |
| `[SFL-CI-01] Store::CodeInsightsSource` | New |
| `[SFL-CI-02] :analytic register, payloads, AnalyticLoader` | New |
| `[SFL-CI-03] rake insights:reground` | New |
| `[SFL-CI-04] Langfuse grounding eval and calibration` | New |
| `[SFL-CI-05] :tool_trace register and ToolTraceLoader` | New |

**Blocked on SFL-ING-22.** Tasks 5 onward cannot start until the register catalog exists. Tasks 1-4 can proceed in parallel with it.

---

## File structure

| File | Responsibility |
|---|---|
| `lib/sfl/core/refs/row_ref.rb` | A database row presented as a readable ref |
| `lib/sfl/core/types/insight/decision_payload.rb` | Validated `decision` payload |
| `lib/sfl/core/types/insight/learning_payload.rb` | Validated `learning` payload |
| `lib/sfl/core/types/insight/summary_payload.rb` | Validated `summary` payload |
| `lib/sfl/core/types/insight/prompt_quality_payload.rb` | Validated `prompt_quality` payload (numeric) |
| `lib/sfl/core/types/tool_trace_payload.rb` | Validated tool-trace payload |
| `lib/sfl/store/code_insights_source.rb` | Read-only origin, three scopes, `#stats` |
| `lib/sfl/core/loaders/analytic_source.rb` | Cuts insight Units, dispatches on `insight_type` |
| `lib/sfl/core/loaders/tool_trace_source.rb` | Cuts tool-trace Units |
| `lib/sfl/analysis/evidence_reference.rb` | Parses `"Assistant#3: quote"` |
| `lib/sfl/analysis/grounding_scorer.rb` | Two-arm grounding score |
| `lib/tasks/insights.rake` | `rake insights:reground` |

---

### Task 0: Amend SFL-ING-16 and SFL-ING-22 on the board

**Files:** none. This task edits trackboi cards.

**Interfaces:**
- Produces: the `Ref` contract and `RegisterProfile` requirements every later task assumes.

- [ ] **Step 1: Amend SFL-ING-16 acceptance criteria**

Replace the first two criteria with:

```
- [ ] `#each_ref` yields **Ref**s (not specifically FileRefs), `NotImplementedError` convention,
      `#refs` free method built on it; lazy `Enumerator` semantics
- [ ] Ref contract: `#read(limit = nil)`, `#name`, `#extension`, `#content_identity`,
      `#size_bytes`, `#mtime` (nil-able), `#source_id`. Deliberately not a path.
      `FileRef` is the filesystem/git implementation; non-file origins supply their own.
```

Rationale to record on the card: a SQLite row is not a file, and widening the contract before the port is built costs one word in a signature. After SFL-ING-16 ships and 13 loaders are converted, it costs a migration.

- [ ] **Step 2: Amend SFL-ING-22 acceptance criteria**

Change `#analyze(file_ref, services)` to `#analyze(ref, services)`, and append:

```
- [ ] A register may declare MORE THAN ONE Unit payload shape, resolved from a
      discriminator on the ref, not from the register name alone
      (`:analytic` carries four: decision, learning, summary, prompt_quality)
- [ ] Payload shapes may hold non-prose fields (Hash, Float), not text only
- [ ] Registers can be registered from OUTSIDE `Core::Loaders` without editing core
- [ ] A register may declare itself excluded from default retrieval
      (`:tool_trace` is aggregated, never synthesized into prose)
- [ ] A register may declare itself excluded from classification, so it does NOT
      appear in `ClassificationSignature`'s derived `Mode` enum
```

- [ ] **Step 3: Record the classification interaction as a card comment on SFL-ING-22**

SFL-ING-22 already requires `ClassificationSignature`'s `Mode` enum be derived from `registry.names`. `:tool_trace` is routed structurally (empty `content` + non-empty `tool_calls`), never classified by an LLM. Without the exclusion flag, adding it silently widens the classifier prompt with a mode the classifier must never choose.

- [ ] **Step 4: Create the five SFL-CI cards in `backlog`, linked to the Ingest/Parser Hexagon Refactor track**

---

### Task 1: RowRef

**Files:**
- Create: `lib/sfl/core/refs/row_ref.rb`
- Test: `spec/core/refs/row_ref_spec.rb`

**Interfaces:**
- Consumes: the Ref contract from Task 0.
- Produces: `RowRef.new(row:, source_id:, name:, extension: "json")` with `#read(limit = nil) -> String` (JSON), `#content_identity -> String`, `#size_bytes -> Integer`, `#mtime -> nil`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Refs::RowRef do
  subject(:ref) do
    described_class.new(
      row: { id: "abc-123", type: "decision", title: "Use Thor", timestamp: "2026-09-13T15:34:00Z" },
      source_id: "code_insights:insights",
      name: "insight:abc-123"
    )
  end

  it "reads the row as JSON" do
    expect(JSON.parse(ref.read)).to include("id" => "abc-123", "title" => "Use Thor")
  end

  it "truncates when given a limit" do
    expect(ref.read(10).length).to eq(10)
  end

  it "derives content_identity from the row id and timestamp" do
    expect(ref.content_identity).to eq("abc-123:2026-09-13T15:34:00Z")
  end

  it "reports size_bytes as the bytesize of the JSON document" do
    expect(ref.size_bytes).to eq(ref.read.bytesize)
  end

  it "has no mtime, because a row is not a file" do
    expect(ref.mtime).to be_nil
  end

  it "defaults extension to json" do
    expect(ref.extension).to eq("json")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/core/refs/row_ref_spec.rb`
Expected: FAIL, `uninitialized constant SFL::Core::Refs`

- [ ] **Step 3: Write minimal implementation**

```ruby
# frozen_string_literal: true

require "json"

module SFL
  module Core
    module Refs
      # A database row presented as a readable ref. The DB counterpart of
      # FileRef: same contract, no filesystem. `content_identity` is the
      # row's own id plus its timestamp, which is the closest thing a row
      # has to FileRef's mtime+size identity.
      class RowRef
        attr_reader :name, :extension, :source_id

        def initialize(row:, source_id:, name:, extension: "json")
          @row = row
          @source_id = source_id
          @name = name
          @extension = extension
        end

        def read(limit = nil)
          doc = JSON.generate(@row)
          limit ? doc[0, limit] : doc
        end

        def content_identity
          "#{@row[:id]}:#{@row[:timestamp]}"
        end

        def size_bytes
          read.bytesize
        end

        # A row has no filesystem mtime. Nil-able by the Ref contract.
        def mtime
          nil
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/core/refs/row_ref_spec.rb`
Expected: PASS, 6 examples

- [ ] **Step 5: Run the zeitwerk gate**

Run: `bundle exec rake zeitwerk:check`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/sfl/core/refs/row_ref.rb spec/core/refs/row_ref_spec.rb
git commit -m "feat(ingest): RowRef, a database row as a readable ref"
```

---

### Task 2: Insight payload structs

**Files:**
- Create: `lib/sfl/core/types/insight/decision_payload.rb`, `learning_payload.rb`, `summary_payload.rb`, `prompt_quality_payload.rb`
- Test: `spec/core/types/insight_payloads_spec.rb`

**Interfaces:**
- Produces: `Insight::DecisionPayload`, `Insight::LearningPayload`, `Insight::SummaryPayload`, `Insight::PromptQualityPayload`, each a `Dry::Struct` with `.from_metadata(hash)` and `#to_h`.

Field names come from the measured source schema. Counts are how many of the 26,244 rows carry each key.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "insight payloads" do
  describe SFL::Core::Types::Insight::DecisionPayload do
    subject(:payload) do
      described_class.from_metadata(
        "situation" => "Five binstubs disagreed.",
        "choice" => "Collapse into one Thor entrypoint.",
        "reasoning" => "Dispatch was duplicated.",
        "alternatives" => [{ "option" => "Keep shims", "rejected_because" => "Two code paths." }],
        "trade_offs" => "Breaks muscle memory.",
        "revisit_when" => "If a shim is needed for CI.",
        "evidence" => ["Assistant#3: delete them outright"]
      )
    end

    it "keeps revisit_when as a typed field" do
      expect(payload.revisit_when).to eq("If a shim is needed for CI.")
    end

    it "keeps alternatives structured, not stringified" do
      expect(payload.alternatives.first["rejected_because"]).to eq("Two code paths.")
    end

    it "tolerates a missing trade_offs, which 2 of 8186 rows lack" do
      p2 = described_class.from_metadata("situation" => "s", "choice" => "c", "reasoning" => "r")
      expect(p2.trade_offs).to be_nil
    end

    it "defaults evidence to an empty array" do
      expect(described_class.from_metadata({}).evidence).to eq([])
    end
  end

  describe SFL::Core::Types::Insight::PromptQualityPayload do
    subject(:payload) do
      described_class.from_metadata(
        "takeaways" => "Front-load constraints.",
        "findings" => "Three clarifying rounds.",
        "message_overhead" => "high",
        "efficiency_score" => 0.42,
        "dimension_scores" => { "clarity" => 0.5, "specificity" => 0.3 }
      )
    end

    it "keeps efficiency_score a Float, not a String" do
      expect(payload.efficiency_score).to eq(0.42)
      expect(payload.efficiency_score).to be_a(Float)
    end

    it "keeps dimension_scores a Hash" do
      expect(payload.dimension_scores).to eq("clarity" => 0.5, "specificity" => 0.3)
    end

    it "coerces an integer efficiency_score to Float" do
      p2 = described_class.from_metadata("efficiency_score" => 1)
      expect(p2.efficiency_score).to eq(1.0)
    end
  end

  describe SFL::Core::Types::Insight::LearningPayload do
    it "carries the five learning keys" do
      payload = described_class.from_metadata(
        "takeaway" => "Graph tools fail silently.",
        "symptom" => "Empty braces returned.",
        "root_cause" => "Index staleness.",
        "applies_when" => "After a large external update.",
        "evidence" => ["User#0: it returned {}"]
      )
      expect(payload.takeaway).to eq("Graph tools fail silently.")
      expect(payload.evidence).to eq(["User#0: it returned {}"])
    end
  end

  describe SFL::Core::Types::Insight::SummaryPayload do
    it "carries claim and outcome" do
      payload = described_class.from_metadata("claim" => "Ingest hardening", "outcome" => "Four cards filed.")
      expect(payload.outcome).to eq("Four cards filed.")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/core/types/insight_payloads_spec.rb`
Expected: FAIL, `uninitialized constant SFL::Core::Types::Insight`

- [ ] **Step 3: Write the four payload structs**

```ruby
# frozen_string_literal: true
# lib/sfl/core/types/insight/decision_payload.rb

module SFL
  module Core
    module Types
      module Insight
        # The `decision` metadata schema from code-insights. All seven keys
        # are optional because the corpus is not uniform: 8,186 rows carry
        # situation/reasoning/alternatives, 8,184 carry choice/trade_offs,
        # 8,181 carry revisit_when/evidence.
        class DecisionPayload < Dry::Struct
          attribute :claim, Types::String.optional.default(nil)
          attribute :situation, Types::String.optional.default(nil)
          attribute :choice, Types::String.optional.default(nil)
          attribute :reasoning, Types::String.optional.default(nil)
          attribute :alternatives, Types::Array.of(Types::Hash).default([].freeze)
          attribute :trade_offs, Types::String.optional.default(nil)
          attribute :revisit_when, Types::String.optional.default(nil)
          attribute :evidence, Types::Array.of(Types::String).default([].freeze)

          def self.from_metadata(meta)
            new(
              claim: meta["claim"],
              situation: meta["situation"],
              choice: meta["choice"],
              reasoning: meta["reasoning"],
              alternatives: Array(meta["alternatives"]),
              trade_offs: meta["trade_offs"],
              revisit_when: meta["revisit_when"],
              evidence: Array(meta["evidence"]).map(&:to_s)
            )
          end
        end
      end
    end
  end
end
```

```ruby
# frozen_string_literal: true
# lib/sfl/core/types/insight/learning_payload.rb

module SFL
  module Core
    module Types
      module Insight
        class LearningPayload < Dry::Struct
          attribute :takeaway, Types::String.optional.default(nil)
          attribute :symptom, Types::String.optional.default(nil)
          attribute :root_cause, Types::String.optional.default(nil)
          attribute :applies_when, Types::String.optional.default(nil)
          attribute :evidence, Types::Array.of(Types::String).default([].freeze)

          def self.from_metadata(meta)
            new(
              takeaway: meta["takeaway"],
              symptom: meta["symptom"],
              root_cause: meta["root_cause"],
              applies_when: meta["applies_when"],
              evidence: Array(meta["evidence"]).map(&:to_s)
            )
          end
        end
      end
    end
  end
end
```

```ruby
# frozen_string_literal: true
# lib/sfl/core/types/insight/summary_payload.rb

module SFL
  module Core
    module Types
      module Insight
        class SummaryPayload < Dry::Struct
          attribute :claim, Types::String.optional.default(nil)
          attribute :outcome, Types::String.optional.default(nil)

          def self.from_metadata(meta)
            new(claim: meta["claim"], outcome: meta["outcome"])
          end
        end
      end
    end
  end
end
```

```ruby
# frozen_string_literal: true
# lib/sfl/core/types/insight/prompt_quality_payload.rb

module SFL
  module Core
    module Types
      module Insight
        # The numeric payload. This is the shape that forces
        # "payloads may hold non-prose fields" onto SFL-ING-22.
        class PromptQualityPayload < Dry::Struct
          attribute :takeaways, Types::String.optional.default(nil)
          attribute :findings, Types::String.optional.default(nil)
          attribute :message_overhead, Types::String.optional.default(nil)
          attribute :efficiency_score, Types::Coercible::Float.optional.default(nil)
          attribute :dimension_scores, Types::Hash.default({}.freeze)

          def self.from_metadata(meta)
            new(
              takeaways: meta["takeaways"]&.to_s,
              findings: meta["findings"]&.to_s,
              message_overhead: meta["message_overhead"]&.to_s,
              efficiency_score: meta["efficiency_score"],
              dimension_scores: meta["dimension_scores"] || {}
            )
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/core/types/insight_payloads_spec.rb`
Expected: PASS, 10 examples

- [ ] **Step 5: Commit**

```bash
git add lib/sfl/core/types/insight spec/core/types/insight_payloads_spec.rb
git commit -m "feat(types): typed payload structs for the four insight schemas"
```

---

### Task 3: ToolTracePayload

**Files:**
- Create: `lib/sfl/core/types/tool_trace_payload.rb`
- Test: `spec/core/types/tool_trace_payload_spec.rb`

**Interfaces:**
- Produces: `ToolTracePayload.from_row(row, sequence_index:)` with `#tool_name`, `#arguments`, `#result_status`, `#result_size`, `#thinking`, `#sequence_index`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Types::ToolTracePayload do
  it "extracts the tool name from a tool_calls JSON payload" do
    payload = described_class.from_row(
      { tool_calls: '[{"name":"Bash","input":{"command":"ls"}}]', tool_results: '[{"status":"ok"}]', thinking: nil },
      sequence_index: 4
    )

    expect(payload.tool_name).to eq("Bash")
    expect(payload.sequence_index).to eq(4)
  end

  it "records result_size as the bytesize of tool_results" do
    payload = described_class.from_row({ tool_calls: '[{"name":"Read"}]', tool_results: '[{"status":"ok"}]' }, sequence_index: 0)
    expect(payload.result_size).to eq('[{"status":"ok"}]'.bytesize)
  end

  it "marks result_status error when the result carries an error key" do
    payload = described_class.from_row(
      { tool_calls: '[{"name":"Bash"}]', tool_results: '[{"error":"exit 1"}]' },
      sequence_index: 1
    )
    expect(payload.result_status).to eq("error")
  end

  it "falls back to unknown tool_name on malformed tool_calls JSON" do
    payload = described_class.from_row({ tool_calls: "not json", tool_results: nil }, sequence_index: 0)
    expect(payload.tool_name).to eq("unknown")
  end

  it "keeps thinking text when the message carries only thinking" do
    payload = described_class.from_row({ tool_calls: nil, tool_results: nil, thinking: "weighing options" }, sequence_index: 2)
    expect(payload.thinking).to eq("weighing options")
    expect(payload.tool_name).to eq("unknown")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/core/types/tool_trace_payload_spec.rb`
Expected: FAIL, `uninitialized constant SFL::Core::Types::ToolTracePayload`

- [ ] **Step 3: Write minimal implementation**

```ruby
# frozen_string_literal: true

require "json"

module SFL
  module Core
    module Types
      # One tool invocation, extracted from a message whose `content` is
      # empty but whose tool_calls/tool_results/thinking are not. 190,747
      # of 282,074 messages are this shape.
      class ToolTracePayload < Dry::Struct
        attribute :tool_name, Types::String.default("unknown")
        attribute :arguments, Types::Hash.default({}.freeze)
        attribute :result_status, Types::String.default("unknown")
        attribute :result_size, Types::Integer.default(0)
        attribute :thinking, Types::String.optional.default(nil)
        attribute :sequence_index, Types::Integer

        def self.from_row(row, sequence_index:)
          calls = parse(row[:tool_calls])
          first = calls.is_a?(Array) ? calls.first : nil
          results = row[:tool_results].to_s

          new(
            tool_name: first.is_a?(Hash) ? (first["name"] || "unknown") : "unknown",
            arguments: first.is_a?(Hash) ? (first["input"] || {}) : {},
            result_status: status_for(results),
            result_size: results.bytesize,
            thinking: row[:thinking],
            sequence_index: sequence_index
          )
        end

        # Malformed JSON is expected in a corpus this size; a bad tool_calls
        # blob degrades to "unknown" rather than failing the whole run.
        def self.parse(raw)
          raw.nil? || raw.to_s.strip.empty? ? nil : JSON.parse(raw)
        rescue JSON::ParserError
          nil
        end
        private_class_method :parse

        def self.status_for(results)
          return "unknown" if results.strip.empty?

          results.include?('"error"') ? "error" : "ok"
        end
        private_class_method :status_for
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/core/types/tool_trace_payload_spec.rb`
Expected: PASS, 5 examples

- [ ] **Step 5: Commit**

```bash
git add lib/sfl/core/types/tool_trace_payload.rb spec/core/types/tool_trace_payload_spec.rb
git commit -m "feat(types): ToolTracePayload for tool-only messages"
```

---

### Task 4: Evidence reference parsing

**Files:**
- Create: `lib/sfl/analysis/evidence_reference.rb`
- Test: `spec/analysis/evidence_reference_spec.rb`

**Interfaces:**
- Produces: `EvidenceReference.parse(String) -> EvidenceReference | nil`, with `#speaker`, `#turn_index`, `#quote`.

This is the parser for the string form measured in the corpus: `"Assistant#3: I also noticed the script used an undefined log function"`. 87.7% of these quotes do not resolve to any text in their own session, so the parser must be total: it never raises, and returns `nil` only when there is no usable quote at all.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::EvidenceReference do
  it "parses speaker, turn index, and quote" do
    ref = described_class.parse("Assistant#3: Two logical units detected.")

    expect(ref.speaker).to eq("Assistant")
    expect(ref.turn_index).to eq(3)
    expect(ref.quote).to eq("Two logical units detected.")
  end

  it "parses a User reference" do
    ref = described_class.parse("User#0: only commit staged files")
    expect(ref.speaker).to eq("User")
    expect(ref.turn_index).to eq(0)
  end

  it "keeps a colon inside the quote" do
    ref = described_class.parse("Assistant#1: Staged: kando configs only.")
    expect(ref.quote).to eq("Staged: kando configs only.")
  end

  it "returns a ref with nil turn_index when there is no speaker prefix" do
    ref = described_class.parse("just a bare sentence with no prefix")

    expect(ref.speaker).to be_nil
    expect(ref.turn_index).to be_nil
    expect(ref.quote).to eq("just a bare sentence with no prefix")
  end

  it "returns nil for an empty quote" do
    expect(described_class.parse("Assistant#3: ")).to be_nil
  end

  it "returns nil for nil input" do
    expect(described_class.parse(nil)).to be_nil
  end

  it "returns nil for a non-string input" do
    expect(described_class.parse({ "option" => "x" })).to be_nil
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/analysis/evidence_reference_spec.rb`
Expected: FAIL, `uninitialized constant SFL::Analysis::EvidenceReference`

- [ ] **Step 3: Write minimal implementation**

```ruby
# frozen_string_literal: true

module SFL
  module Analysis
    # Parses a code-insights `evidence` entry, which looks like
    # "Assistant#3: <quote>". The prefix is a claim about provenance, not
    # a verified one: measured on 2026-09-14, 87.7% of these quotes do not
    # appear anywhere in their own session, and turn indices frequently
    # point at empty messages. The parser therefore records what was
    # claimed and leaves verification to GroundingScorer.
    class EvidenceReference
      PATTERN = /\A(?<speaker>User|Human|Assistant|System)#(?<index>\d+):\s*(?<quote>.+)\z/m

      attr_reader :speaker, :turn_index, :quote

      def initialize(speaker:, turn_index:, quote:)
        @speaker = speaker
        @turn_index = turn_index
        @quote = quote
      end

      # @return [EvidenceReference, nil] nil when there is no usable quote
      def self.parse(entry)
        return nil unless entry.is_a?(String)

        if (m = PATTERN.match(entry.strip))
          quote = m[:quote].strip
          return nil if quote.empty?

          return new(speaker: m[:speaker], turn_index: Integer(m[:index]), quote: quote)
        end

        bare = entry.strip
        return nil if bare.empty?

        new(speaker: nil, turn_index: nil, quote: bare)
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/analysis/evidence_reference_spec.rb`
Expected: PASS, 7 examples

- [ ] **Step 5: Commit**

```bash
git add lib/sfl/analysis/evidence_reference.rb spec/analysis/evidence_reference_spec.rb
git commit -m "feat(analysis): parse code-insights evidence references"
```

---

### Task 5: Grounding scorer, citation-fidelity arm

**Files:**
- Create: `lib/sfl/analysis/grounding_scorer.rb`
- Test: `spec/analysis/grounding_scorer_spec.rb`

**Interfaces:**
- Consumes: `EvidenceReference.parse` (Task 4).
- Produces: `GroundingScorer.new(weights:, threshold:, instrumenter:)` with `#citation_fidelity(evidence_entries, sibling_texts) -> Float` returning 0.0..1.0.

The arm scores each quote on a three-level scale and takes the mean. This is the version corrected during spec review: highest matching level wins, not a fallback chain.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::GroundingScorer do
  subject(:scorer) do
    described_class.new(
      weights: { citation: 0.5, message: 0.3, session: 0.2 },
      threshold: 0.4,
      instrumenter: SFL::Core::Ports::Null::Instrumenter.new
    )
  end

  let(:siblings) { ["I have updated the ensure_gum function to check /usr/bin/gum first.", "only commit staged files"] }

  describe "#citation_fidelity" do
    it "scores 1.0 for a verbatim quote" do
      score = scorer.citation_fidelity(["Assistant#3: check /usr/bin/gum first"], siblings)
      expect(score).to eq(1.0)
    end

    it "is case and whitespace insensitive" do
      score = scorer.citation_fidelity(["Assistant#3:  CHECK   /usr/bin/gum   FIRST "], siblings)
      expect(score).to eq(1.0)
    end

    it "scores 0.5 when only the leading tokens match" do
      score = scorer.citation_fidelity(
        ["Assistant#3: I have updated the ensure_gum function to do something entirely different"],
        siblings
      )
      expect(score).to eq(0.5)
    end

    it "scores 0.0 for a quote absent from the siblings" do
      score = scorer.citation_fidelity(["Assistant#3: this sentence was never said by anyone"], siblings)
      expect(score).to eq(0.0)
    end

    it "averages across multiple quotes" do
      score = scorer.citation_fidelity(
        ["Assistant#3: check /usr/bin/gum first", "Assistant#4: never said this at all"],
        siblings
      )
      expect(score).to eq(0.5)
    end

    it "returns nil when there are no parseable quotes" do
      expect(scorer.citation_fidelity([], siblings)).to be_nil
    end

    it "returns nil when there are no sibling turns, because absence of evidence is not evidence" do
      expect(scorer.citation_fidelity(["Assistant#3: anything"], [])).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/analysis/grounding_scorer_spec.rb`
Expected: FAIL, `uninitialized constant SFL::Analysis::GroundingScorer`

- [ ] **Step 3: Write minimal implementation**

```ruby
# frozen_string_literal: true

module SFL
  module Analysis
    # Scores how defensible an insight is from the turns it claims to cite.
    #
    # This is NOT a truth score. A well-grounded insight can still be wrong,
    # and `untrusted` means "not defensible from the transcript", nothing
    # more. See the spec's evaluation section.
    class GroundingScorer
      VERBATIM = 1.0
      PARTIAL = 0.5
      ABSENT = 0.0
      LEAD_TOKENS = 6
      OVERLAP_FLOOR = 0.6

      def initialize(weights:, threshold:, instrumenter:)
        @weights = weights
        @threshold = threshold
        @instrumenter = instrumenter
      end

      attr_reader :weights, :threshold, :instrumenter

      # @return [Float, nil] nil when the arm cannot be computed at all
      def citation_fidelity(evidence_entries, sibling_texts)
        return nil if sibling_texts.empty?

        refs = Array(evidence_entries).filter_map { |e| EvidenceReference.parse(e) }
        return nil if refs.empty?

        blob = normalize(sibling_texts.join(" "))
        refs.sum { |ref| level_for(normalize(ref.quote), blob) } / refs.size.to_f
      end

      private def level_for(quote, blob)
        return VERBATIM if blob.include?(quote)

        tokens = quote.split
        return ABSENT if tokens.size < LEAD_TOKENS

        lead = tokens.first(LEAD_TOKENS).join(" ")
        return PARTIAL if blob.include?(lead)

        overlap = tokens.count { |t| blob.include?(t) } / tokens.size.to_f
        overlap >= OVERLAP_FLOOR ? PARTIAL : ABSENT
      end

      private def normalize(text)
        text.to_s.downcase.gsub(/\s+/, " ").strip
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/analysis/grounding_scorer_spec.rb`
Expected: PASS, 7 examples

- [ ] **Step 5: Commit**

```bash
git add lib/sfl/analysis/grounding_scorer.rb spec/analysis/grounding_scorer_spec.rb
git commit -m "feat(analysis): citation-fidelity arm of the grounding scorer"
```

---

### Task 6: Grounding scorer, cosine arms and combined score

**Files:**
- Modify: `lib/sfl/analysis/grounding_scorer.rb`
- Modify: `spec/analysis/grounding_scorer_spec.rb`

**Interfaces:**
- Consumes: `#citation_fidelity` (Task 5).
- Produces: `#score(evidence_entries:, sibling_texts:, insight_vector:, sibling_vectors:, session_vector:) -> Hash` with keys `:citation_fidelity`, `:message_cosine`, `:session_cosine`, `:grounding`, `:untrusted`, `:grounded_by_index`.

**This task implements the nil invariant, which is the single most important property in the plan.** When `grounding` is nil, `untrusted` must be true.

- [ ] **Step 1: Write the failing test**

```ruby
  describe "#score" do
    let(:v_a) { [1.0, 0.0, 0.0] }
    let(:v_b) { [0.0, 1.0, 0.0] }

    it "sets grounded_by_index to the closest sibling vector" do
      result = scorer.score(
        evidence_entries: ["Assistant#3: check /usr/bin/gum first"],
        sibling_texts: siblings,
        insight_vector: v_a,
        sibling_vectors: [v_b, v_a],
        session_vector: v_a
      )

      expect(result[:grounded_by_index]).to eq(1)
      expect(result[:message_cosine]).to be_within(1e-6).of(1.0)
    end

    it "combines the three arms with the configured weights" do
      result = scorer.score(
        evidence_entries: ["Assistant#3: check /usr/bin/gum first"],
        sibling_texts: siblings,
        insight_vector: v_a,
        sibling_vectors: [v_a],
        session_vector: v_a
      )

      expect(result[:grounding]).to be_within(1e-6).of(1.0)
      expect(result[:untrusted]).to be(false)
    end

    it "flags untrusted below the threshold" do
      result = scorer.score(
        evidence_entries: ["Assistant#3: never said this at all"],
        sibling_texts: siblings,
        insight_vector: v_a,
        sibling_vectors: [v_b],
        session_vector: v_b
      )

      expect(result[:grounding]).to be < 0.4
      expect(result[:untrusted]).to be(true)
    end

    it "returns nil grounding and untrusted true when there are no sibling turns" do
      result = scorer.score(
        evidence_entries: ["Assistant#3: anything"],
        sibling_texts: [], insight_vector: v_a, sibling_vectors: [], session_vector: nil
      )

      expect(result[:grounding]).to be_nil
      expect(result[:untrusted]).to be(true)
    end

    it "NEVER marks trusted when grounding is nil, for any weight configuration" do
      [{ citation: 1.0, message: 0.0, session: 0.0 },
       { citation: 0.0, message: 0.0, session: 1.0 },
       { citation: 0.34, message: 0.33, session: 0.33 }].each do |weights|
        s = described_class.new(weights: weights, threshold: 0.0,
                                instrumenter: SFL::Core::Ports::Null::Instrumenter.new)
        result = s.score(evidence_entries: [], sibling_texts: [],
                         insight_vector: nil, sibling_vectors: [], session_vector: nil)

        expect(result[:grounding]).to be_nil
        expect(result[:untrusted]).to be(true), "threshold 0.0 must not trust a nil score"
      end
    end

    it "emits one instrumented span per scored insight" do
      spy = instance_spy(SFL::Core::Ports::Null::Instrumenter)
      allow(spy).to receive(:instrument).and_yield
      s = described_class.new(weights: { citation: 1.0, message: 0.0, session: 0.0 },
                              threshold: 0.4, instrumenter: spy)

      s.score(evidence_entries: ["Assistant#3: check /usr/bin/gum first"], sibling_texts: siblings,
              insight_vector: v_a, sibling_vectors: [v_a], session_vector: v_a)

      expect(spy).to have_received(:instrument).with("insights.reground", hash_including(:grounding))
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/analysis/grounding_scorer_spec.rb -e "#score"`
Expected: FAIL, `undefined method 'score'`

- [ ] **Step 3: Add the cosine arms and the combined score**

Add to `GroundingScorer`:

```ruby
      # @return [Hash] the full scoring record for one insight
      def score(evidence_entries:, sibling_texts:, insight_vector:, sibling_vectors:, session_vector:)
        citation = citation_fidelity(evidence_entries, sibling_texts)
        best_index, message_cosine = best_sibling(insight_vector, sibling_vectors)
        session_cosine = cosine(insight_vector, session_vector)

        grounding = combine(citation, message_cosine, session_cosine)

        record = {
          citation_fidelity: citation,
          message_cosine: message_cosine,
          session_cosine: session_cosine,
          grounding: grounding,
          # The nil invariant: no score means not defensible, for every
          # weight configuration and every threshold, including 0.0.
          untrusted: grounding.nil? || grounding < threshold,
          grounded_by_index: best_index
        }

        instrumenter.instrument("insights.reground", record) { record }
      end

      # Weights are renormalized over the arms that actually produced a
      # value, so a missing arm does not silently drag the score toward
      # zero. All arms missing means nil, never 0.0.
      private def combine(citation, message_cosine, session_cosine)
        parts = [[citation, weights[:citation]],
                 [message_cosine, weights[:message]],
                 [session_cosine, weights[:session]]].reject { |value, _| value.nil? }
        return nil if parts.empty?

        total_weight = parts.sum { |_, w| w }
        return nil if total_weight.zero?

        parts.sum { |value, w| value * w } / total_weight
      end

      private def best_sibling(insight_vector, sibling_vectors)
        return [nil, nil] if insight_vector.nil? || sibling_vectors.empty?

        scored = sibling_vectors.each_with_index.filter_map do |vector, index|
          c = cosine(insight_vector, vector)
          c.nil? ? nil : [index, c]
        end
        return [nil, nil] if scored.empty?

        scored.max_by { |_, c| c }
      end

      private def cosine(a, b)
        return nil if a.nil? || b.nil? || a.empty? || b.empty? || a.size != b.size

        dot = a.zip(b).sum { |x, y| x * y }
        magnitude = Math.sqrt(a.sum { |x| x * x }) * Math.sqrt(b.sum { |y| y * y })
        magnitude.zero? ? nil : dot / magnitude
      end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/analysis/grounding_scorer_spec.rb`
Expected: PASS, 13 examples

- [ ] **Step 5: Commit**

```bash
git add lib/sfl/analysis/grounding_scorer.rb spec/analysis/grounding_scorer_spec.rb
git commit -m "feat(analysis): cosine arms, weighted grounding, nil invariant"
```

---

### Task 7: Store::CodeInsightsSource, sessions scope and read-only enforcement

**Files:**
- Create: `lib/sfl/store/code_insights_source.rb`
- Create: `spec/fixtures/code_insights/telemetry.db` (built by the spec, see Step 1)
- Test: `spec/store/code_insights_source_spec.rb`

**Interfaces:**
- Consumes: `RowRef` (Task 1).
- Produces: `CodeInsightsSource.new(path:)` with `#each_ref(scope:) -> Enumerator<RowRef>` for `:sessions`, `:messages`, `:insights`, `:tool_traces`, plus `#stats -> Hash`.

Build the fixture from a real anonymized slice, not synthetic rows. The 87.7% citation finding exists only because real data was checked; synthetic fixtures would have looked clean.

- [ ] **Step 1: Write the fixture builder and the failing test**

```ruby
# frozen_string_literal: true

require "spec_helper"
require "sqlite3"

RSpec.describe SFL::Store::CodeInsightsSource do
  subject(:source) { described_class.new(path: db_path) }

  let(:db_path) { "spec/fixtures/code_insights/telemetry.db" }

  before(:all) do
    FileUtils.mkdir_p("spec/fixtures/code_insights")
    path = "spec/fixtures/code_insights/telemetry.db"
    FileUtils.rm_f(path)
    db = SQLite3::Database.new(path)
    db.execute_batch(<<~SQL)
      CREATE TABLE sessions (id TEXT PRIMARY KEY, project_name TEXT, summary TEXT,
                             started_at TEXT, source_tool TEXT);
      CREATE TABLE messages (id TEXT PRIMARY KEY, session_id TEXT, type TEXT,
                             content TEXT DEFAULT '', thinking TEXT, tool_calls TEXT,
                             tool_results TEXT, timestamp TEXT, embedding_status TEXT);
      CREATE TABLE insights (id TEXT PRIMARY KEY, session_id TEXT, project_name TEXT,
                             type TEXT, title TEXT, summary TEXT, confidence REAL,
                             metadata TEXT, timestamp TEXT);
      CREATE TABLE embedding_metadata (id TEXT PRIMARY KEY, entity_type TEXT, entity_id TEXT,
                                       model TEXT, dim INTEGER, source_text TEXT);

      INSERT INTO sessions VALUES ('s1','yadm','Committed staged dotfiles.','2026-09-13T00:34:00Z','claude-code');

      INSERT INTO messages VALUES ('m0','s1','user','only commit staged files',NULL,NULL,NULL,'2026-09-13T00:30:00Z','pending');
      INSERT INTO messages VALUES ('m1','s1','assistant','',NULL,'[{"name":"Bash","input":{"command":"git status"}}]','[{"status":"ok"}]','2026-09-13T00:31:00Z','pending');
      INSERT INTO messages VALUES ('m2','s1','assistant','Staged: kando configs only.',NULL,NULL,NULL,'2026-09-13T00:32:00Z','pending');
      INSERT INTO messages VALUES ('m3','s1','assistant','',  'weighing options',NULL,NULL,'2026-09-13T00:33:00Z','pending');
      INSERT INTO messages VALUES ('m4','s1','assistant','',NULL,NULL,NULL,'2026-09-13T00:33:30Z','pending');

      INSERT INTO insights VALUES ('i1','s1','yadm','decision','Restrict commit to staged files',
        'Committed only staged files.',0.9,
        '{"situation":"Unstaged files present.","choice":"Commit staged only.","reasoning":"User asked.","alternatives":[],"trade_offs":"Leaves work uncommitted.","revisit_when":"When the user is ready.","evidence":["User#0: only commit staged files"]}',
        '2026-09-13T00:34:00Z');
      INSERT INTO insights VALUES ('i2','s1','yadm','prompt_quality','Front-load constraints',
        'Constraints arrived late.',0.7,
        '{"takeaways":"Front-load constraints.","findings":"One clarifying round.","message_overhead":"low","efficiency_score":0.42,"dimension_scores":{"clarity":0.5}}',
        '2026-09-13T00:35:00Z');
      INSERT INTO insights VALUES ('i3','s1','yadm','decision','Broken metadata','x',0.5,'not json','2026-09-13T00:36:00Z');
      INSERT INTO insights VALUES ('i4','s1','yadm','learning','Wrong dimension','x',0.5,'{"takeaway":"t"}','2026-09-13T00:37:00Z');

      INSERT INTO embedding_metadata VALUES ('e4','insight','i4','qwen3-embedding:0.6b',1024,'x');
    SQL
    db.close
  end

  it "yields one ref per session" do
    refs = source.each_ref(scope: :sessions).to_a
    expect(refs.map(&:name)).to eq(["session:s1"])
  end

  it "opens the database read-only" do
    expect { source.execute!("INSERT INTO sessions VALUES ('s2','x','y','z','w')") }
      .to raise_error(SQLite3::ReadOnlyException)
  end

  it "is lazy: the first ref arrives before enumeration finishes" do
    enum = source.each_ref(scope: :messages)
    expect(enum.first).to be_a(SFL::Core::Refs::RowRef)
  end

  it "tags every ref with a scope-specific source_id" do
    expect(source.each_ref(scope: :sessions).first.source_id).to eq("code_insights:sessions")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/store/code_insights_source_spec.rb`
Expected: FAIL, `uninitialized constant SFL::Store::CodeInsightsSource`

- [ ] **Step 3: Write minimal implementation**

```ruby
# frozen_string_literal: true

require "sqlite3"
require "json"

module SFL
  module Store
    # Read-only origin over a code-insights telemetry database.
    #
    # Opened with `?mode=ro` so an ingest run can never write to the
    # operator's telemetry. Three ingest scopes route to three registers;
    # `:sessions` yields the parent clauses the other three hang from.
    class CodeInsightsSource
      SCOPES = %i[sessions messages insights tool_traces].freeze
      EXPECTED_DIM = 768

      class UnknownScopeError < StandardError; end

      def initialize(path:, busy_timeout_ms: 5_000)
        @path = File.expand_path(path)
        @stats = Hash.new(0)
        @db = SQLite3::Database.new("file:#{@path}?mode=ro", results_as_hash: true, readonly: true)
        @db.busy_timeout = busy_timeout_ms
      end

      attr_reader :stats

      def each_ref(scope:, &block)
        raise UnknownScopeError, "unknown scope #{scope.inspect}" unless SCOPES.include?(scope)
        return to_enum(:each_ref, scope: scope) unless block_given?

        send(:"each_#{scope}", &block)
      end

      # Exposed so the read-only guarantee is testable rather than assumed.
      def execute!(sql)
        @db.execute(sql)
      end

      def close
        @db.close
      end

      private def each_sessions
        @db.execute("SELECT * FROM sessions ORDER BY started_at, id") do |row|
          yield ref_for(row, scope: :sessions, name: "session:#{row['id']}")
        end
      end

      private def ref_for(row, scope:, name:)
        Core::Refs::RowRef.new(
          row: symbolize(row),
          source_id: "code_insights:#{scope}",
          name: name
        )
      end

      private def symbolize(row)
        row.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/store/code_insights_source_spec.rb`
Expected: PASS, 4 examples

- [ ] **Step 5: Commit**

```bash
git add lib/sfl/store/code_insights_source.rb spec/store/code_insights_source_spec.rb
git commit -m "feat(store): read-only CodeInsightsSource with sessions scope"
```

---

### Task 8: Messages and tool-trace routing

**Files:**
- Modify: `lib/sfl/store/code_insights_source.rb`
- Modify: `spec/store/code_insights_source_spec.rb`

**Interfaces:**
- Produces: `:messages` and `:tool_traces` scopes, and `stats[:routed_tool_trace]`.

The routing rule, measured: a message with empty `content` and any of `thinking`/`tool_calls`/`tool_results` is a tool trace, not dialogue. 190,747 of 282,074 messages are this shape. A message empty on all four is skipped entirely (14,529 expected).

- [ ] **Step 1: Write the failing test**

```ruby
  describe "message and tool-trace routing" do
    it "routes non-empty content to :messages" do
      names = source.each_ref(scope: :messages).map(&:name)
      expect(names).to eq(["message:m0", "message:m2"])
    end

    it "routes empty content with tool_calls to :tool_traces" do
      names = source.each_ref(scope: :tool_traces).map(&:name)
      expect(names).to eq(["trace:m1", "trace:m3"])
    end

    it "counts tool traces as routed, not skipped" do
      source.each_ref(scope: :tool_traces).to_a
      expect(source.stats[:routed_tool_trace]).to eq(2)
      expect(source.stats[:skipped_tool_only]).to eq(0)
    end

    it "skips a message that is empty on content, thinking, and tools" do
      source.each_ref(scope: :messages).to_a
      expect(source.stats[:skipped_empty]).to eq(1)
    end

    it "assigns sequence_index by timestamp within the session" do
      ref = source.each_ref(scope: :tool_traces).first
      expect(JSON.parse(ref.read)["sequence_index"]).to eq(1)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/store/code_insights_source_spec.rb -e "routing"`
Expected: FAIL, `unknown scope :tool_traces` is handled but the methods are missing

- [ ] **Step 3: Add the routing methods**

```ruby
      MESSAGE_SQL = <<~SQL
        SELECT m.*,
               ROW_NUMBER() OVER (PARTITION BY m.session_id ORDER BY m.timestamp, m.id) - 1 AS sequence_index
        FROM messages m
        ORDER BY m.session_id, m.timestamp, m.id
      SQL

      private def each_messages
        @db.execute(MESSAGE_SQL) do |row|
          case classify(row)
          when :dialogue then yield ref_for(row, scope: :messages, name: "message:#{row['id']}")
          when :empty then @stats[:skipped_empty] += 1
          end
        end
      end

      private def each_tool_traces
        @db.execute(MESSAGE_SQL) do |row|
          next unless classify(row) == :tool_trace

          @stats[:routed_tool_trace] += 1
          yield ref_for(row, scope: :tool_traces, name: "trace:#{row['id']}")
        end
      end

      # A message is dialogue when it has prose. It is a tool trace when it
      # has none but carries thinking or tool traffic. Everything else is
      # empty and contributes nothing to any register.
      private def classify(row)
        return :dialogue unless row["content"].to_s.strip.empty?

        residue = [row["thinking"], row["tool_calls"], row["tool_results"]]
        residue.any? { |v| !v.to_s.strip.empty? } ? :tool_trace : :empty
      end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/store/code_insights_source_spec.rb`
Expected: PASS, 9 examples

- [ ] **Step 5: Commit**

```bash
git add lib/sfl/store/code_insights_source.rb spec/store/code_insights_source_spec.rb
git commit -m "feat(store): route tool-only messages to the tool_trace scope"
```

---

### Task 9: Insights scope with dimension and metadata exclusion

**Files:**
- Modify: `lib/sfl/store/code_insights_source.rb`
- Modify: `spec/store/code_insights_source_spec.rb`

**Interfaces:**
- Produces: `:insights` scope, `stats[:skipped_bad_metadata]`, `stats[:skipped_wrong_dim]`.

- [ ] **Step 1: Write the failing test**

```ruby
  describe "insights scope" do
    it "yields insights with parseable metadata" do
      expect(source.each_ref(scope: :insights).map(&:name)).to eq(["insight:i1", "insight:i2"])
    end

    it "skips a row whose metadata is not JSON" do
      source.each_ref(scope: :insights).to_a
      expect(source.stats[:skipped_bad_metadata]).to eq(1)
    end

    it "skips a row embedded at a non-768 dimension" do
      source.each_ref(scope: :insights).to_a
      expect(source.stats[:skipped_wrong_dim]).to eq(1)
    end

    it "accounts for every source row" do
      source.each_ref(scope: :insights).to_a
      ingested = 2
      skipped = source.stats[:skipped_bad_metadata] + source.stats[:skipped_wrong_dim]
      expect(ingested + skipped).to eq(4)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/store/code_insights_source_spec.rb -e "insights scope"`
Expected: FAIL, `undefined method 'each_insights'`

- [ ] **Step 3: Add the insights scope**

```ruby
      INSIGHT_SQL = <<~SQL
        SELECT i.*, em.dim AS embedding_dim
        FROM insights i
        LEFT JOIN embedding_metadata em
          ON em.entity_type = 'insight'
         AND i.id = COALESCE(NULLIF(em.entity_id, ''), em.id)
        GROUP BY i.id
        ORDER BY i.timestamp, i.id
      SQL

      private def each_insights
        @db.execute(INSIGHT_SQL) do |row|
          dim = row["embedding_dim"]
          if !dim.nil? && dim != EXPECTED_DIM
            @stats[:skipped_wrong_dim] += 1
            next
          end

          parsed = parse_metadata(row["metadata"])
          if parsed.nil?
            @stats[:skipped_bad_metadata] += 1
            next
          end

          enriched = symbolize(row).merge(parsed_metadata: parsed)
          yield Core::Refs::RowRef.new(
            row: enriched, source_id: "code_insights:insights", name: "insight:#{row['id']}"
          )
        end
      end

      private def parse_metadata(raw)
        return nil if raw.to_s.strip.empty?

        parsed = JSON.parse(raw)
        parsed.is_a?(Hash) ? parsed : nil
      rescue JSON::ParserError
        nil
      end
```

Note the join: `vec_insights`-style chunk rows carry the real insight id in `entity_id`, and only fall back to `id`. Joining on `id` alone would miss the chunked majority.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/store/code_insights_source_spec.rb`
Expected: PASS, 13 examples

- [ ] **Step 5: Run the full gate**

Run: `bundle exec rake`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/sfl/store/code_insights_source.rb spec/store/code_insights_source_spec.rb
git commit -m "feat(store): insights scope with dimension and metadata exclusion"
```

---

### Task 10: AnalyticSource loader

**Files:**
- Create: `lib/sfl/core/loaders/analytic_source.rb`
- Test: `spec/core/loaders/analytic_source_spec.rb`

**Interfaces:**
- Consumes: insight payload structs (Task 2), `RowRef` (Task 1).
- Produces: `AnalyticSource.new(ref)` implementing `Core::Loaders::Source`; one `Unit` per insight.

**Blocked on SFL-ING-22.** Cannot merge until the register catalog exists.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::AnalyticSource do
  def ref_for(row)
    SFL::Core::Refs::RowRef.new(row: row, source_id: "code_insights:insights", name: "insight:#{row[:id]}")
  end

  let(:decision_row) do
    { id: "i1", session_id: "s1", project_name: "yadm", type: "decision",
      title: "Restrict commit to staged files", confidence: 0.9,
      timestamp: "2026-09-13T00:34:00Z",
      parsed_metadata: { "situation" => "Unstaged files present.", "choice" => "Commit staged only.",
                         "revisit_when" => "When the user is ready.",
                         "evidence" => ["User#0: only commit staged files"] } }
  end

  it "is a Loaders::Source" do
    expect(described_class.new(ref_for(decision_row))).to be_a(SFL::Core::Loaders::Source)
  end

  it "keeps revisit_when as a typed payload field, not prose" do
    unit = described_class.new(ref_for(decision_row)).units.first
    expect(unit.metadata["payload"]["revisit_when"]).to eq("When the user is ready.")
  end

  it "tags the register and insight type" do
    unit = described_class.new(ref_for(decision_row)).units.first
    expect(unit.metadata["register"]).to eq("analytic")
    expect(unit.metadata["insight_type"]).to eq("decision")
  end

  it "renders prose into text for annotation and embedding" do
    unit = described_class.new(ref_for(decision_row)).units.first
    expect(unit.text).to include("Restrict commit to staged files")
    expect(unit.text).to include("Commit staged only.")
  end

  it "keeps a numeric prompt_quality payload numeric" do
    row = decision_row.merge(
      id: "i2", type: "prompt_quality", title: "Front-load constraints",
      parsed_metadata: { "efficiency_score" => 0.42, "dimension_scores" => { "clarity" => 0.5 } }
    )
    unit = described_class.new(ref_for(row)).units.first

    expect(unit.metadata["payload"]["efficiency_score"]).to eq(0.42)
    expect(unit.metadata["payload"]["dimension_scores"]).to eq("clarity" => 0.5)
  end

  it "raises on an unregistered insight type rather than silently losing fields" do
    row = decision_row.merge(type: "brand_new_type")
    expect { described_class.new(ref_for(row)).units }
      .to raise_error(described_class::UnknownInsightTypeError, /brand_new_type/)
  end

  it "sets document_id and leaves speaker nil, because an insight is not a turn" do
    unit = described_class.new(ref_for(decision_row)).units.first
    expect(unit.document_id).to eq("insight:i1")
    expect(unit.speaker).to be_nil
    expect(unit.is_user).to be(false)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/core/loaders/analytic_source_spec.rb`
Expected: FAIL, `uninitialized constant SFL::Core::Loaders::AnalyticSource`

- [ ] **Step 3: Write minimal implementation**

```ruby
# frozen_string_literal: true

module SFL
  module Core
    module Loaders
      # Cuts one Unit per code-insights insight. Core::Types::Unit is a
      # closed Dry::Struct and is not reopened: the differing schemas are
      # validated into typed payloads and carried in metadata, the same
      # pattern json_source.rb and csv_source.rb already use.
      class AnalyticSource
        include Source

        class UnknownInsightTypeError < StandardError; end

        PAYLOADS = {
          "decision" => Types::Insight::DecisionPayload,
          "learning" => Types::Insight::LearningPayload,
          "summary" => Types::Insight::SummaryPayload,
          "prompt_quality" => Types::Insight::PromptQualityPayload
        }.freeze

        def initialize(ref)
          @ref = ref
          @row = JSON.parse(ref.read, symbolize_names: true)
        end

        def each_unit
          return to_enum(:each_unit) unless block_given?

          yield build_unit
        end

        private def build_unit
          type = @row[:type].to_s
          klass = PAYLOADS.fetch(type) do
            # Loud, not lossy: a new upstream insight type must be modelled,
            # never absorbed into a generic shape that drops its fields.
            raise UnknownInsightTypeError, "no payload registered for insight type #{type.inspect}"
          end

          payload = klass.from_metadata(stringify(@row[:parsed_metadata] || {}))

          Types::Unit.new(
            document_id: "insight:#{@row[:id]}",
            text: render_text(type, payload),
            speaker: nil,
            is_user: false,
            sent_at: parse_time(@row[:timestamp]),
            metadata: {
              "register" => "analytic",
              "insight_type" => type,
              "project_name" => @row[:project_name],
              "confidence" => @row[:confidence],
              "session_id" => @row[:session_id],
              "source_tool" => @row[:source_tool],
              "payload" => stringify(payload.to_h)
            }
          )
        end

        # Annotation and embedding need prose; the payload stays the
        # queryable form.
        private def render_text(type, payload)
          parts =
            case type
            when "decision" then [@row[:title], payload.choice, payload.situation, payload.reasoning]
            when "learning" then [payload.takeaway, payload.symptom, payload.root_cause]
            when "summary" then [@row[:title], payload.outcome]
            when "prompt_quality" then [@row[:title], payload.takeaways, payload.findings]
            end

          parts.compact.reject { |p| p.to_s.strip.empty? }.join("\n\n")
        end

        private def parse_time(raw)
          raw.nil? ? nil : Time.parse(raw.to_s)
        rescue ArgumentError
          nil
        end

        private def stringify(hash)
          hash.each_with_object({}) do |(k, v), h|
            h[k.to_s] = v.is_a?(Hash) ? stringify(v) : v
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/core/loaders/analytic_source_spec.rb`
Expected: PASS, 7 examples

- [ ] **Step 5: Commit**

```bash
git add lib/sfl/core/loaders/analytic_source.rb spec/core/loaders/analytic_source_spec.rb
git commit -m "feat(loaders): AnalyticSource cuts insight Units with typed payloads"
```

---

### Task 11: ToolTraceSource loader

**Files:**
- Create: `lib/sfl/core/loaders/tool_trace_source.rb`
- Test: `spec/core/loaders/tool_trace_source_spec.rb`

**Interfaces:**
- Consumes: `ToolTracePayload` (Task 3), `RowRef` (Task 1).
- Produces: `ToolTraceSource.new(ref)` implementing `Core::Loaders::Source`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::ToolTraceSource do
  subject(:loader) { described_class.new(ref) }

  let(:ref) do
    SFL::Core::Refs::RowRef.new(
      row: { id: "m1", session_id: "s1", project_name: "yadm", sequence_index: 1,
             tool_calls: '[{"name":"Bash","input":{"command":"git status"}}]',
             tool_results: '[{"status":"ok"}]', timestamp: "2026-09-13T00:31:00Z" },
      source_id: "code_insights:tool_traces", name: "trace:m1"
    )
  end

  it "is a Loaders::Source" do
    expect(loader).to be_a(SFL::Core::Loaders::Source)
  end

  it "tags the tool_trace register" do
    expect(loader.units.first.metadata["register"]).to eq("tool_trace")
  end

  it "puts the tool name and sequence index in the payload" do
    payload = loader.units.first.metadata["payload"]
    expect(payload["tool_name"]).to eq("Bash")
    expect(payload["sequence_index"]).to eq(1)
  end

  it "renders a short text summary rather than the full argument blob" do
    expect(loader.units.first.text).to eq("Bash git status")
  end

  it "marks the unit as excluded from embedding, so redrive skips it" do
    expect(loader.units.first.metadata["embed"]).to be(false)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/core/loaders/tool_trace_source_spec.rb`
Expected: FAIL, `uninitialized constant SFL::Core::Loaders::ToolTraceSource`

- [ ] **Step 3: Write minimal implementation**

```ruby
# frozen_string_literal: true

module SFL
  module Core
    module Loaders
      # Cuts one Unit per tool invocation. This register exists to be
      # aggregated, never synthesized into prose, so its units are marked
      # non-embeddable: 190,747 of them would otherwise enter the
      # embedding queue for no retrieval benefit.
      class ToolTraceSource
        include Source

        SUMMARY_LIMIT = 80

        def initialize(ref)
          @ref = ref
          @row = JSON.parse(ref.read, symbolize_names: true)
        end

        def each_unit
          return to_enum(:each_unit) unless block_given?

          payload = Types::ToolTracePayload.from_row(@row, sequence_index: @row[:sequence_index].to_i)

          yield Types::Unit.new(
            document_id: "trace:#{@row[:id]}",
            text: summarize(payload),
            speaker: nil,
            is_user: false,
            sent_at: parse_time(@row[:timestamp]),
            metadata: {
              "register" => "tool_trace",
              "embed" => false,
              "session_id" => @row[:session_id],
              "project_name" => @row[:project_name],
              "source_tool" => @row[:source_tool],
              "payload" => payload.to_h.transform_keys(&:to_s)
            }
          )
        end

        private def summarize(payload)
          arg = payload.arguments.values.first.to_s[0, SUMMARY_LIMIT]
          [payload.tool_name, arg].reject { |p| p.to_s.strip.empty? }.join(" ")
        end

        private def parse_time(raw)
          raw.nil? ? nil : Time.parse(raw.to_s)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/core/loaders/tool_trace_source_spec.rb`
Expected: PASS, 5 examples

- [ ] **Step 5: Commit**

```bash
git add lib/sfl/core/loaders/tool_trace_source.rb spec/core/loaders/tool_trace_source_spec.rb
git commit -m "feat(loaders): ToolTraceSource, non-embeddable tool-trace units"
```

---

### Task 12: rake insights:reground

**Files:**
- Create: `lib/tasks/insights.rake`
- Modify: `Rakefile` (load `lib/tasks/*.rake` alongside the existing `db:` and `embeddings:` namespaces)
- Test: `spec/tasks/insights_reground_spec.rb`

**Interfaces:**
- Consumes: `GroundingScorer#score` (Task 6).
- Produces: `rake insights:reground`, rewriting `untrusted`, `modality_weight`, and `grounded_by` on analytic clauses.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "rake insights:reground" do
  subject(:regrounder) { SFL::Analysis::Regrounder.new(db: db, scorer: scorer) }

  let(:scorer) do
    SFL::Analysis::GroundingScorer.new(
      weights: { citation: 1.0, message: 0.0, session: 0.0 },
      threshold: 0.4,
      instrumenter: SFL::Core::Ports::Null::Instrumenter.new
    )
  end

  it "clears untrusted on a well-grounded insight and records the citing clause" do
    regrounder.call
    row = db[:interpersonal_payloads].where(clause_id: "insight:i1").first

    expect(row[:untrusted]).to be(false)
    expect(row[:modality_weight]).to eq(1.0)
    expect(row[:grounded_by]).to eq("message:m0")
  end

  it "leaves untrusted true when no quote resolves" do
    regrounder.call
    expect(db[:interpersonal_payloads].where(clause_id: "insight:i9").first[:untrusted]).to be(true)
  end

  it "leaves untrusted true and modality_weight nil when the session has no sibling turns" do
    regrounder.call
    row = db[:interpersonal_payloads].where(clause_id: "insight:i8").first

    expect(row[:untrusted]).to be(true)
    expect(row[:modality_weight]).to be_nil
  end

  it "is idempotent: a second run produces identical rows" do
    regrounder.call
    first = db[:interpersonal_payloads].order(:clause_id).all
    regrounder.call

    expect(db[:interpersonal_payloads].order(:clause_id).all).to eq(first)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/tasks/insights_reground_spec.rb`
Expected: FAIL, `uninitialized constant SFL::Analysis::Regrounder`

- [ ] **Step 3: Write the regrounder and the rake task**

```ruby
# frozen_string_literal: true

module SFL
  module Analysis
    # Pass 2b. Rewrites grounding state on analytic clauses from their
    # sibling conversation clauses under the same parent.
    #
    # Idempotent by construction: every field it writes is derived only
    # from current state, never accumulated.
    class Regrounder
      def initialize(db:, scorer:)
        @db = db
        @scorer = scorer
      end

      def call
        analytic_clauses.each do |clause|
          siblings = sibling_turns(clause[:parent_clause_id])

          result = @scorer.score(
            evidence_entries: evidence_for(clause),
            sibling_texts: siblings.map { |s| s[:text] },
            insight_vector: vector_for(clause[:external_id]),
            sibling_vectors: siblings.map { |s| vector_for(s[:external_id]) },
            session_vector: vector_for(clause[:parent_clause_id])
          )

          index = result[:grounded_by_index]
          @db[:interpersonal_payloads].where(clause_id: clause[:external_id]).update(
            untrusted: result[:untrusted],
            modality_weight: result[:grounding],
            grounded_by: index.nil? ? nil : siblings[index][:external_id],
            annotation_source: "code_insights:v1"
          )
        end
      end

      private def analytic_clauses
        @db[:clauses].where(register: "analytic").order(:external_id).all
      end

      private def sibling_turns(parent_id)
        return [] if parent_id.nil?

        @db[:clauses].where(parent_clause_id: parent_id, register: "conversation").order(:external_id).all
      end

      private def evidence_for(clause)
        payload = clause[:payload].is_a?(String) ? JSON.parse(clause[:payload]) : (clause[:payload] || {})
        Array(payload["evidence"])
      rescue JSON::ParserError
        []
      end

      private def vector_for(external_id)
        return nil if external_id.nil?

        row = @db[:embeddings].where(clause_id: external_id).first
        row && row[:vector]
      end
    end
  end
end
```

```ruby
# frozen_string_literal: true
# lib/tasks/insights.rake

namespace :insights do
  desc "Pass 2b: recompute grounding on analytic clauses"
  task :reground do
    require "sfl"

    boot = SFL::Boot.call
    scorer = SFL::Analysis::GroundingScorer.new(
      weights: SFL::Config.grounding_weights,
      threshold: SFL::Config.grounding_threshold,
      instrumenter: boot.instrumenter
    )
    SFL::Analysis::Regrounder.new(db: boot.db, scorer: scorer).call
  end
end
```

Add to `Rakefile`, next to the existing `db:` and `embeddings:` namespaces:

```ruby
Dir.glob("lib/tasks/*.rake").each { |f| load f }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/tasks/insights_reground_spec.rb`
Expected: PASS, 4 examples

- [ ] **Step 5: Run the full gate**

Run: `bundle exec rake`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/sfl/analysis/regrounder.rb lib/tasks/insights.rake Rakefile spec/tasks/insights_reground_spec.rb
git commit -m "feat(analysis): rake insights:reground, pass 2b"
```

---

### Task 13: Langfuse grounding eval

**Files:**
- Create: `docs/superpowers/specs/grounding-eval-dataset.md` (labeling protocol)
- Create: `lib/sfl/analysis/grounding_eval.rb`
- Test: `spec/analysis/grounding_eval_spec.rb`

**Interfaces:**
- Consumes: `GroundingScorer#score` (Task 6).
- Produces: `GroundingEval.new(dataset:, scorer:).call -> Hash` with `:precision`, `:recall`, `:nil_invariant_violations`, `:defensible_agreement`, `:correct_agreement`.

The dataset carries two independent labels per item: *defensible from transcript* and *actually correct*. Divergence between the scorer's agreement with each is the signal that the metric has drifted into pretending to be a truth score.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::GroundingEval do
  subject(:eval_run) { described_class.new(dataset: dataset, scorer: scorer).call }

  let(:scorer) do
    SFL::Analysis::GroundingScorer.new(
      weights: { citation: 1.0, message: 0.0, session: 0.0 },
      threshold: 0.4,
      instrumenter: SFL::Core::Ports::Null::Instrumenter.new
    )
  end

  let(:dataset) do
    [
      { evidence: ["Assistant#1: commit staged only"], siblings: ["commit staged only"],
        defensible: true, correct: true },
      { evidence: ["Assistant#1: never uttered"], siblings: ["commit staged only"],
        defensible: false, correct: true },
      { evidence: [], siblings: [], defensible: false, correct: false }
    ]
  end

  it "reports zero nil-invariant violations for a correct scorer" do
    expect(eval_run[:nil_invariant_violations]).to eq(0)
  end

  it "measures agreement with the defensible label" do
    expect(eval_run[:defensible_agreement]).to eq(1.0)
  end

  it "measures agreement with the correct label separately" do
    expect(eval_run[:correct_agreement]).to be < eval_run[:defensible_agreement]
  end

  it "reports precision and recall against the defensible label" do
    expect(eval_run[:precision]).to eq(1.0)
    expect(eval_run[:recall]).to eq(1.0)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/analysis/grounding_eval_spec.rb`
Expected: FAIL, `uninitialized constant SFL::Analysis::GroundingEval`

- [ ] **Step 3: Write minimal implementation**

```ruby
# frozen_string_literal: true

module SFL
  module Analysis
    # Scores the grounding scorer against a hand-labeled dataset.
    #
    # Two labels per item, deliberately independent: `defensible` (is the
    # claim supported by the transcript) and `correct` (is the claim true).
    # Grounding predicts the first. If `correct_agreement` starts tracking
    # `defensible_agreement`, the metric has drifted into claiming
    # something it cannot know.
    class GroundingEval
      def initialize(dataset:, scorer:)
        @dataset = dataset
        @scorer = scorer
      end

      def call
        results = @dataset.map do |item|
          scored = @scorer.score(
            evidence_entries: item[:evidence],
            sibling_texts: item[:siblings],
            insight_vector: item[:insight_vector],
            sibling_vectors: Array(item[:sibling_vectors]),
            session_vector: item[:session_vector]
          )
          item.merge(predicted_defensible: !scored[:untrusted], grounding: scored[:grounding])
        end

        {
          nil_invariant_violations: results.count { |r| r[:grounding].nil? && r[:predicted_defensible] },
          defensible_agreement: agreement(results, :defensible),
          correct_agreement: agreement(results, :correct),
          precision: precision(results),
          recall: recall(results)
        }
      end

      private def agreement(results, label)
        results.count { |r| r[:predicted_defensible] == r[label] } / results.size.to_f
      end

      private def precision(results)
        predicted = results.select { |r| r[:predicted_defensible] }
        return 1.0 if predicted.empty?

        predicted.count { |r| r[:defensible] } / predicted.size.to_f
      end

      private def recall(results)
        actual = results.select { |r| r[:defensible] }
        return 1.0 if actual.empty?

        actual.count { |r| r[:predicted_defensible] } / actual.size.to_f
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/analysis/grounding_eval_spec.rb`
Expected: PASS, 4 examples

- [ ] **Step 5: Write the labeling protocol doc**

`docs/superpowers/specs/grounding-eval-dataset.md` must state: stratify across insight `type`, across projects, and across the resolvable/unresolvable split; label `defensible` by reading only the session transcript; label `correct` independently; target a few hundred items; pick `tau` from the precision/recall curve rather than intuition.

- [ ] **Step 6: Commit**

```bash
git add lib/sfl/analysis/grounding_eval.rb spec/analysis/grounding_eval_spec.rb docs/superpowers/specs/grounding-eval-dataset.md
git commit -m "feat(analysis): grounding eval with independent defensible/correct labels"
```

---

## Self-review

**Spec coverage.** D1 → Tasks 7-11. D2 → Task 10 plus Task 0 amendments. D3 → Tasks 0, 1. D4 → Tasks 7-9 write `untrusted` true at ingest, Task 12 rewrites it. D5 → Pass 2a is the existing `rake embeddings:redrive`, no new task; Task 11 marks tool traces non-embeddable so they stay out of it. D6 → Tasks 6, 13. D7 → Tasks 2, 10. D8 → Tasks 3, 11. D9 → Task 9.

**Gaps deliberately left.** The register profiles themselves (`Registers::Catalog.register_into`) are SFL-ING-22's deliverable, not this plan's; Tasks 10 and 11 provide the loaders those profiles will wrap. Wiring `CodeInsightsSource` into `Ingest::Orchestrator` belongs to SFL-ING-09, which already exists. Session parent-clause creation depends on the ingest orchestrator and is deferred until SFL-ING-09 and SFL-ING-22 land.

**Type consistency.** `#stats` keys are `:routed_tool_trace`, `:skipped_empty`, `:skipped_bad_metadata`, `:skipped_wrong_dim` everywhere. `GroundingScorer#score` returns `:grounded_by_index` (an Array index); `Regrounder` resolves it to `grounded_by` (a clause id) before writing. `metadata["payload"]` is string-keyed in both loaders.

**Known risk.** Task 12's `Regrounder` assumes `clauses.register`, `clauses.payload`, `interpersonal_payloads.grounded_by`, and `embeddings.vector` columns. `grounded_by` does not exist yet and needs a migration, which belongs with SFL-ING-22's schema work. Confirm the other three column names against the live schema before starting Task 12.
