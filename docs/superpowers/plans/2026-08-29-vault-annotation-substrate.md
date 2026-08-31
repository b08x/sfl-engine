# Vault Annotation Substrate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pair vault attachments to their parent notes, and derive interpersonal mood/modality from spaCy output without an LLM.

**Scope note (2026-08-31):** audio/video loading was removed from this plan and now lives in `2026-08-31-media-ingest-and-onboarding-design.md`. What remains is pairing plus rules-based annotation — five tasks, no media handling.

**Architecture:** Two independent slices. `Ingest::Pairing` (+ its `AttachmentSet` value object) is pure filesystem logic — it binds each vault attachment to the note it belongs to and records how it knew. `Annotation::RulesAnnotator` (+ its `ModalityLexicon`) derives `mood` and `modality_weight` from `SyntacticToken` fields Pass 1 already persists, introducing a `"rules"` provenance value and a per-field trust predicate. Neither slice touches the other; both depend on existing code only through published types.

**Tech Stack:** Ruby 4.0, Zeitwerk, Dry::Struct/Dry::Types, RSpec, RuboCop (shopify + performance + rake + rspec + sequel + thread_safety), `amatch` (Jaro-Winkler). No new gems required — `amatch` is already in the Gemfile.

**Spec:** `docs/superpowers/specs/2026-08-29-vault-annotation-substrate-design.md` — read it alongside this plan

**Working directory:** this repository (`sfl-engine`). Branch before the first commit.

## Global Constraints

- **No LLM on any path in this plan.** No task may call a provider, require an API key, or widen `Boot.call`. Every unit here is local and deterministic.
- **`Loaders::Source` is a module (duck), not a base class.** Implement `#each_unit` yielding `SFL::Core::Types::Unit`; `#units` comes free. Never implement both.
- **`each_unit` returns an enumerator when no block is given** — `return to_enum(:each_unit) unless block_given?` is the first line, matching every existing loader.
- **Extraction failure emits a flagged `Unit`, never a drop and never a raise.** Precedent: `ImageSource` emits a stub with `"vision_failed" => true`.
- **Never fabricate a value to fill a field.** Absent data stays `nil`. Precedent: `Analysis::CorrelationAnalyzer` reports `nil` rather than a `0.5` midpoint.
- **Zeitwerk naming is enforced by a spec.** `spec/zeitwerk_spec.rb` eager-loads the whole tree; a file/constant mismatch fails the suite. `lib/sfl/ingest/pairing.rb` must define `SFL::Ingest::Pairing`.
- **`spec/` mirrors `lib/`.** `lib/sfl/ingest/pairing.rb` → `spec/ingest/pairing_spec.rb`.
- **Every spec file starts** `# frozen_string_literal: true`, blank line, `require "spec_helper"`.
- **Every lib file starts** `# frozen_string_literal: true`.
- **Run RuboCop before every commit.** `bundle exec rubocop` must be clean. Disables require an inline `--` reason, matching existing style.
- **Ruby 4.0 shorthand hash syntax** (`text:`, `height:`) is used throughout this codebase. Match it.

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/sfl/ingest/attachment_set.rb` | Value object: one parent note + its attachments + pairing provenance |
| `lib/sfl/ingest/pairing.rb` | Walks a vault root, binds attachments to notes by embed / folder / unpaired |
| `lib/sfl/annotation/modality_lexicon.rb` | Frozen modal / hedge / booster lemma tables |
| `lib/sfl/annotation/rules_annotator.rb` | `SyntacticClause` → `InterpersonalPayload` with `annotation_source: "rules"` |
| `lib/sfl/core/types/annotation_source.rb` | **Modify** — add `"rules"` to the enum |
| `lib/sfl/core/types/trusted_annotation_sources.rb` | **Modify** — add a per-field trust predicate |

Tasks 1–2 (pairing) are independent of Tasks 3–5 (provenance and annotation). All five can run in any order; none share a file.

---

### Task 1: `AttachmentSet` value object

**Files:**
- Create: `lib/sfl/ingest/attachment_set.rb`
- Test: `spec/ingest/attachment_set_spec.rb`

**Interfaces:**
- Consumes: `Dry::Struct`, `SFL::Core::Types` (already loaded by `lib/sfl.rb`)
- Produces: `SFL::Ingest::AttachmentSet.new(parent_note:, attachments:, strategy:, confidence:)` where `parent_note` is `String | nil`, `attachments` is `Array<String>`, `strategy` is one of `"embed"`, `"folder"`, `"unpaired"`, and `confidence` is `Float` in `0.0..1.0`. Task 2 constructs these; the future workflow wrapper reads `#strategy` and `#confidence`.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/ingest/attachment_set_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Ingest::AttachmentSet do
  it "holds a parent note, its attachments, and the pairing provenance" do
    set = described_class.new(
      parent_note: "Daily/RAG System Architecture.md",
      attachments: ["assets/RAG System Architecture/image-970.png"],
      strategy: "folder",
      confidence: 0.94
    )

    expect(set.parent_note).to eq("Daily/RAG System Architecture.md")
    expect(set.attachments).to eq(["assets/RAG System Architecture/image-970.png"])
    expect(set.strategy).to eq("folder")
    expect(set.confidence).to eq(0.94)
  end

  it "allows a nil parent_note for an orphan attachment" do
    set = described_class.new(
      parent_note: nil, attachments: ["assets/loose.pdf"], strategy: "unpaired", confidence: 0.0
    )

    expect(set.parent_note).to be_nil
  end

  it "rejects a strategy outside the known set" do
    expect {
      described_class.new(parent_note: nil, attachments: [], strategy: "guessed", confidence: 0.0)
    }.to raise_error(Dry::Struct::Error)
  end

  it "rejects a confidence outside 0.0..1.0" do
    expect {
      described_class.new(parent_note: nil, attachments: [], strategy: "embed", confidence: 1.5)
    }.to raise_error(Dry::Struct::Error)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/ingest/attachment_set_spec.rb`
Expected: FAIL — `uninitialized constant SFL::Ingest::AttachmentSet`

- [ ] **Step 3: Write minimal implementation**

```ruby
# lib/sfl/ingest/attachment_set.rb
# frozen_string_literal: true

module SFL
  module Ingest
    # One parent note bound to the attachments that belong to it, plus how
    # that binding was decided. `strategy`/`confidence` travel with the set
    # so a fuzzy folder-name match is never indistinguishable downstream
    # from an exact embed link — Pairing records how it knew, not just what
    # it concluded.
    #
    # `parent_note` is nil for an orphan attachment. That is not an error:
    # an unpaired attachment still yields clauses worth correlating, so it
    # is carried through the pipeline rather than dropped.
    class AttachmentSet < Dry::Struct
      STRATEGIES = %w[embed folder unpaired].freeze

      attribute :parent_note, Core::Types::String.optional
      attribute :attachments, Core::Types::Array.of(Core::Types::String)
      attribute :strategy, Core::Types::String.enum(*STRATEGIES)
      attribute :confidence, Core::Types::Coercible::Float.constrained(gteq: 0.0, lteq: 1.0)
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/ingest/attachment_set_spec.rb`
Expected: PASS (4 examples, 0 failures)

If `Core::Types::String` raises `NameError`, check what `lib/sfl/core/types.rb` exposes and use the same reference the existing `lib/sfl/core/types/unit.rb` uses for its `Types::String` — match that file exactly rather than inventing a path.

- [ ] **Step 5: Verify Zeitwerk and RuboCop**

Run: `bundle exec rspec spec/zeitwerk_spec.rb && bundle exec rubocop lib/sfl/ingest/attachment_set.rb spec/ingest/attachment_set_spec.rb`
Expected: both PASS/clean

- [ ] **Step 6: Commit**

```bash
git add lib/sfl/ingest/attachment_set.rb spec/ingest/attachment_set_spec.rb
git commit -m "✨ feat(ingest): add AttachmentSet value object with pairing provenance"
```

---

### Task 2: `Ingest::Pairing`

**Files:**
- Create: `lib/sfl/ingest/pairing.rb`
- Test: `spec/ingest/pairing_spec.rb`
- Test fixtures: `spec/fixtures/vault/` (created in Step 1)

**Interfaces:**
- Consumes: `SFL::Ingest::AttachmentSet` (Task 1); `Amatch::JaroWinkler` from the `amatch` gem
- Produces: `SFL::Ingest::Pairing.new(vault_root:, threshold: 0.9)` with `#each_set { |AttachmentSet| }` and `#sets`. The future workflow wrapper calls `#sets`.

**Why three strategies:** the vault has only 77 wikilink embeds and 186 markdown embeds against ~700 attachments. Most pairing is conventional — `assets/2024-01-29 RAG System Architecture/image.png` belongs to `Daily/RAG System Architecture.md`. Embed links are exact and win; folder-name similarity is the fallback; unpaired is a valid outcome, not a failure.

- [ ] **Step 1: Create the fixture vault**

```bash
mkdir -p spec/fixtures/vault/Daily
mkdir -p "spec/fixtures/vault/assets/RAG System Architecture"
mkdir -p spec/fixtures/vault/assets/Orphans

# Note that embeds an attachment explicitly
cat > spec/fixtures/vault/Daily/Embedded.md <<'MD'
# Embedded

![[diagram.png]]
MD

# Note paired only by folder name
cat > "spec/fixtures/vault/Daily/RAG System Architecture.md" <<'MD'
# RAG System Architecture

Notes on the retrieval pipeline.
MD

printf 'fake-png' > spec/fixtures/vault/assets/diagram.png
printf 'fake-png' > "spec/fixtures/vault/assets/RAG System Architecture/image-970.png"
printf 'fake-pdf' > spec/fixtures/vault/assets/Orphans/loose.pdf
```

- [ ] **Step 2: Write the failing test**

```ruby
# spec/ingest/pairing_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Ingest::Pairing do
  let(:root) { "spec/fixtures/vault" }
  let(:sets) { described_class.new(vault_root: root).sets }

  def set_for(basename)
    sets.find { |s| s.attachments.any? { |a| File.basename(a) == basename } }
  end

  it "pairs an explicitly embedded attachment to its embedding note, at full confidence" do
    set = set_for("diagram.png")

    expect(set.strategy).to eq("embed")
    expect(set.confidence).to eq(1.0)
    expect(File.basename(set.parent_note)).to eq("Embedded.md")
  end

  it "pairs a folder-named attachment to the note its folder resembles" do
    set = set_for("image-970.png")

    expect(set.strategy).to eq("folder")
    expect(File.basename(set.parent_note)).to eq("RAG System Architecture.md")
    expect(set.confidence).to be > 0.9
  end

  it "reports an attachment matching no note as unpaired rather than dropping it" do
    set = set_for("loose.pdf")

    expect(set.strategy).to eq("unpaired")
    expect(set.parent_note).to be_nil
    expect(set.confidence).to eq(0.0)
  end

  it "yields every attachment in the vault exactly once" do
    paired = sets.flat_map(&:attachments).map { |a| File.basename(a) }

    expect(paired).to contain_exactly("diagram.png", "image-970.png", "loose.pdf")
  end

  it "prefers the embed strategy when a file could also match a folder" do
    expect(set_for("diagram.png").strategy).to eq("embed")
  end

  context "when the folder similarity falls below the threshold" do
    let(:sets) { described_class.new(vault_root: root, threshold: 0.99).sets }

    it "reports unpaired rather than accepting a weak match" do
      expect(set_for("image-970.png").strategy).to eq("unpaired")
    end
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/ingest/pairing_spec.rb`
Expected: FAIL — `uninitialized constant SFL::Ingest::Pairing`

- [ ] **Step 4: Write the implementation**

```ruby
# lib/sfl/ingest/pairing.rb
# frozen_string_literal: true

require "amatch"

module SFL
  module Ingest
    # Binds each vault attachment to the note it belongs to.
    #
    # Linking in this vault is mostly conventional rather than explicit —
    # 77 wikilink embeds and 186 markdown embeds against ~700 attachments —
    # so an embed-only pairing would orphan almost everything. Three
    # strategies run in order and the first hit wins:
    #
    #   1. embed    — the note body references the file (![[x]] or ![](x))
    #   2. folder   — the attachment's directory name resembles a note title
    #   3. unpaired — no match; still emitted, never dropped
    #
    # Jaro-Winkler (not exact match) because folder names drift from note
    # titles by punctuation and date prefixes far more often than by word
    # choice, and Jaro-Winkler weights a shared prefix, which is exactly
    # where that drift is absent.
    class Pairing
      WIKILINK_EMBED = /!\[\[([^\]|]+)/
      MARKDOWN_EMBED = /!\[[^\]]*\]\(([^)]+)\)/
      NOTE_EXTENSION = ".md"

      # Anything that is not a note is a candidate attachment.
      IGNORED_DIRECTORIES = %w[.git .obsidian .trash node_modules graphify-out].freeze

      DEFAULT_THRESHOLD = 0.9

      # @param vault_root [String]
      # @param threshold [Float] minimum Jaro-Winkler similarity for a folder match
      def initialize(vault_root:, threshold: DEFAULT_THRESHOLD)
        @vault_root = vault_root.to_s
        @threshold = threshold
      end

      # @yield [AttachmentSet]
      # @return [Enumerator] if no block given
      def each_unit = each_set

      def each_set(&block)
        return to_enum(:each_set) unless block

        attachments.each { |path| block.call(pair(path)) }
      end

      # @return [Array<AttachmentSet>]
      def sets = each_set.to_a

      private def pair(path)
        embedded_by(path) || folder_matched(path) || unpaired(path)
      end

      private def embedded_by(path)
        basename = File.basename(path)
        note = notes.find { |n| embed_targets(n).include?(basename) }
        return nil unless note

        AttachmentSet.new(parent_note: note, attachments: [path], strategy: "embed", confidence: 1.0)
      end

      private def folder_matched(path)
        folder = File.basename(File.dirname(path))
        best, score = best_note_for(folder)
        return nil if best.nil? || score < @threshold

        AttachmentSet.new(parent_note: best, attachments: [path], strategy: "folder", confidence: score)
      end

      private def unpaired(path)
        AttachmentSet.new(parent_note: nil, attachments: [path], strategy: "unpaired", confidence: 0.0)
      end

      # @return [Array(String, Float), nil] the closest note and its similarity
      private def best_note_for(folder)
        matcher = Amatch::JaroWinkler.new(folder.downcase)
        notes
          .map { |note| [note, matcher.match(File.basename(note, NOTE_EXTENSION).downcase)] }
          .max_by { |(_note, score)| score } || [nil, 0.0]
      end

      private def embed_targets(note)
        @embed_targets ||= {}
        @embed_targets[note] ||= begin
          body = File.read(File.join(@vault_root, note))
          (body.scan(WIKILINK_EMBED) + body.scan(MARKDOWN_EMBED))
            .flatten
            .map { |target| File.basename(target.strip) }
        end
      end

      private def notes
        @notes ||= relative_files.select { |path| File.extname(path) == NOTE_EXTENSION }
      end

      private def attachments
        @attachments ||= relative_files.reject { |path| File.extname(path) == NOTE_EXTENSION }
      end

      private def relative_files
        @relative_files ||= Dir.glob("**/*", base: @vault_root)
          .reject { |path| ignored?(path) }
          .select { |path| File.file?(File.join(@vault_root, path)) }
      end

      private def ignored?(path)
        path.split(File::SEPARATOR).any? { |segment| IGNORED_DIRECTORIES.include?(segment) }
      end
    end
  end
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/ingest/pairing_spec.rb`
Expected: PASS (6 examples, 0 failures)

If `amatch` is not installed, add `gem "amatch", "~> 0.4"` — it is already in the Gemfile for `ClassificationRegistry`, so this should not be needed. If `Amatch::JaroWinkler#match` returns something other than a `Float` in `0.0..1.0`, check the installed gem's own source before adjusting — do not assume the API from memory.

- [ ] **Step 6: Verify Zeitwerk and RuboCop**

Run: `bundle exec rspec spec/zeitwerk_spec.rb && bundle exec rubocop lib/sfl/ingest/pairing.rb spec/ingest/pairing_spec.rb`
Expected: both PASS/clean

- [ ] **Step 7: Smoke-test against the real vault**

Run:
```bash
bundle exec ruby -Ilib -e '
require "sfl"
sets = SFL::Ingest::Pairing.new(vault_root: "/home/b08x/Notebook").sets
puts "total: #{sets.size}"
sets.group_by(&:strategy).each { |s, g| puts "#{s}: #{g.size}" }
'
```
Expected: a total in the high hundreds, with all three strategies represented. **This is a calibration observation, not an assertion** — record the ratio in the commit message. If `unpaired` dominates overwhelmingly, the threshold needs lowering; note it and move on rather than tuning now.

- [ ] **Step 8: Commit**

```bash
git add lib/sfl/ingest/pairing.rb spec/ingest/pairing_spec.rb spec/fixtures/vault
git commit -m "✨ feat(ingest): pair vault attachments to notes by embed, folder, or unpaired"
```

---

## ⚠ Removed 2026-08-31 — media ingest moved to its own spec

`Ports::Transcriber`, `Core::Loaders::AudioSource` and `Ingest::SourceResolver`
were removed from this plan on 2026-08-31.

**Do not implement them from here.** They are superseded by
`docs/superpowers/specs/2026-08-31-media-ingest-and-onboarding-design.md`, which
merges this plan's audio design with the previously-unimplemented Aug 11 spec.
Three things changed materially:

- `#transcribe` returns `Array<Types::TranscriptSegment>`, a named type — not an
  array of Hashes.
- The default backend is `Core::Transcribers::WhisperCpp` (local), and the
  namespace is `Core::Transcribers::*`, not `Llm::Transcribers::*`.
- **`Ingest::SourceResolver` is dropped entirely.** `Ingest::DeterministicRules`
  already performs path-to-loader dispatch and returns
  `{format:, mode:, source_type:}`. The resolver duplicated it. Extend
  `DeterministicRules` with `classify_audio`/`classify_video` instead.

That spec also adds `DeterministicRules`/`KnowledgeBaseSource`/CLI wiring and the
onboarding wizard — neither of which this plan covered. It needs its own plan
before execution. Video is out of scope there too, and gets its own pipeline
later; the only video work that survives is a `DeterministicRules` skip rule, so
`.mp4` files are recognised and skipped rather than falling into
`Ingest::Orchestrator`'s text fallback, which would sample 4KB of binary as prose.

---

### Task 3: Add `"rules"` provenance and a per-field trust predicate

**Files:**
- Modify: `lib/sfl/core/types/annotation_source.rb`
- Modify: `lib/sfl/core/types/trusted_annotation_sources.rb`
- Test: `spec/core/types/annotation_source_spec.rb` (create if absent)

**Interfaces:**
- Produces: `"rules"` as a valid `AnnotationSource`; `SFL::Core::Types.trusted_for?(source, field)` returning `Boolean`

**Why a predicate rather than widening the constant.** `TRUSTED_ANNOTATION_SOURCES` is consumed wherever the codebase asks "can I rely on this annotation" — quality scoring, citation, contradiction adjudication, dataset export. Rules-derived annotations are trustworthy for `mood` and `modality_weight` and supply *nothing* for `tenor` or `speaker_attitude`. Adding `"rules"` to the flat list would silently assert a tenor trust that does not exist, and `CorrelationAnalyzer` would start averaging a field the annotator never set. The existing constant keeps its exact current meaning; the predicate is additive.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/core/types/annotation_source_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "annotation provenance" do # rubocop:disable RSpec/DescribeClass -- covers two related constants, not one class
  describe SFL::Core::Types::AnnotationSource do
    it "accepts the rules source" do
      expect(described_class["rules"]).to eq("rules")
    end

    it "still accepts every pre-existing source" do
      %w[llm fallback stub chunk_artifact human].each do |source|
        expect(described_class[source]).to eq(source)
      end
    end

    it "still rejects an unknown source" do
      expect { described_class["vibes"] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe ".trusted_for?" do
    it "trusts rules for the fields it actually derives" do
      expect(SFL::Core::Types.trusted_for?("rules", :mood)).to be(true)
      expect(SFL::Core::Types.trusted_for?("rules", :modality_weight)).to be(true)
    end

    it "does NOT trust rules for fields it never sets" do
      expect(SFL::Core::Types.trusted_for?("rules", :tenor)).to be(false)
      expect(SFL::Core::Types.trusted_for?("rules", :speaker_attitude)).to be(false)
    end

    it "trusts llm and human for every field" do
      %i[mood modality_weight tenor speaker_attitude].each do |field|
        expect(SFL::Core::Types.trusted_for?("llm", field)).to be(true)
        expect(SFL::Core::Types.trusted_for?("human", field)).to be(true)
      end
    end

    it "trusts compiler-substituted sources for nothing" do
      %w[fallback stub chunk_artifact].each do |source|
        expect(SFL::Core::Types.trusted_for?(source, :mood)).to be(false)
      end
    end
  end

  it "leaves TRUSTED_ANNOTATION_SOURCES unchanged so existing consumers keep their meaning" do
    expect(SFL::Core::Types::TRUSTED_ANNOTATION_SOURCES).to eq(%w[llm human])
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/core/types/annotation_source_spec.rb`
Expected: FAIL — `Dry::Types::ConstraintError` on `"rules"`

- [ ] **Step 3: Add `"rules"` to the enum**

In `lib/sfl/core/types/annotation_source.rb`, extend the comment and the enum:

```ruby
      # Provenance of interpersonal values: "llm" = real Pass 2 annotation,
      # "fallback" = Pass 2 failed and defaults were substituted, "stub" =
      # Pass 2 was skipped entirely (e.g. --pass1-only runs), "chunk_artifact"
      # = value came from a chunk-boundary default rather than a real
      # annotation, "human" = a reviewer supplied/corrected the values via
      # the HITL review flow — distinct from "llm" because the values didn't
      # come from the compiler, but equally trusted for downstream quality
      # scoring and citation (see TrustedAnnotationSources), "rules" =
      # derived deterministically from Pass 1 syntax by
      # Annotation::RulesAnnotator, with no LLM involved. "rules" is trusted
      # only for the fields it actually derives (mood, modality_weight) —
      # see Types.trusted_for? — because it leaves tenor and
      # speaker_attitude nil rather than guessing them.
      AnnotationSource = String.default("llm")
        .enum("llm", "fallback", "stub", "chunk_artifact", "human", "rules")
```

- [ ] **Step 4: Add the per-field predicate**

In `lib/sfl/core/types/trusted_annotation_sources.rb`, keep `TRUSTED_ANNOTATION_SOURCES` exactly as it is and append:

```ruby
      # Interpersonal fields a given annotation_source may be relied on for.
      #
      # Kept separate from TRUSTED_ANNOTATION_SOURCES rather than folded into
      # it: that constant answers "is this annotation reviewed/reliable" for
      # quality scoring and citation, and every existing consumer depends on
      # its current membership. "rules" needs a finer answer — it derives
      # mood and modality_weight from syntax and deliberately leaves tenor
      # and speaker_attitude nil, so adding it to the flat list would assert
      # a tenor trust that does not exist and CorrelationAnalyzer would begin
      # averaging a field nothing ever set.
      TRUSTED_FIELDS_BY_SOURCE = {
        "llm" => %i[mood modality_weight tenor speaker_attitude].freeze,
        "human" => %i[mood modality_weight tenor speaker_attitude].freeze,
        "rules" => %i[mood modality_weight].freeze,
        "fallback" => [].freeze,
        "stub" => [].freeze,
        "chunk_artifact" => [].freeze,
      }.freeze

      # @param source [String] an AnnotationSource value
      # @param field [Symbol] :mood, :modality_weight, :tenor, :speaker_attitude
      # @return [Boolean]
      def self.trusted_for?(source, field)
        TRUSTED_FIELDS_BY_SOURCE.fetch(source, []).include?(field)
      end
```

Note the spec calls `SFL::Core::Types.trusted_for?`. Confirm which module body this file reopens — if `TRUSTED_ANNOTATION_SOURCES` is defined directly on `Types`, then `def self.trusted_for?` lands on `Types` and the spec is correct as written. If it is nested differently, adjust the spec's call path to match the file rather than restructuring the file.

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/core/types/annotation_source_spec.rb`
Expected: PASS (7 examples, 0 failures)

- [ ] **Step 6: Run the FULL suite — this task modifies shared types**

Run: `bundle exec rspec`
Expected: all pre-existing examples still pass. A failure here means an existing consumer assumed the enum was closed; fix the consumer, do not revert the enum.

- [ ] **Step 7: Verify Zeitwerk and RuboCop**

Run: `bundle exec rspec spec/zeitwerk_spec.rb && bundle exec rubocop lib/sfl/core/types spec/core/types/annotation_source_spec.rb`
Expected: both PASS/clean

- [ ] **Step 8: Commit**

```bash
git add lib/sfl/core/types/annotation_source.rb lib/sfl/core/types/trusted_annotation_sources.rb \
        spec/core/types/annotation_source_spec.rb
git commit -m "✨ feat(types): add rules provenance and per-field trust predicate"
```

---

### Task 4: `Annotation::ModalityLexicon`

**Files:**
- Create: `lib/sfl/annotation/modality_lexicon.rb`
- Test: `spec/annotation/modality_lexicon_spec.rb`

**Interfaces:**
- Consumes: nothing
- Produces: `SFL::Annotation::ModalityLexicon.weight_for(lemma) -> Float | nil`, and the frozen tables `MODALS`, `HEDGES`, `BOOSTERS`

Split from the annotator so the linguistic data is editable and reviewable without touching traversal logic — this table is the part most likely to be tuned against real vault output.

Weights are on the same `0.0..1.0` scale as `Types::ModalityWeight`, where low is tentative and high is categorical.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/annotation/modality_lexicon_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Annotation::ModalityLexicon do
  it "scores tentative modals low" do
    expect(described_class.weight_for("might")).to be < 0.4
    expect(described_class.weight_for("could")).to be < 0.4
  end

  it "scores categorical modals high" do
    expect(described_class.weight_for("must")).to be > 0.8
    expect(described_class.weight_for("will")).to be > 0.7
  end

  it "scores hedges low" do
    expect(described_class.weight_for("possibly")).to be < 0.4
  end

  it "scores boosters high" do
    expect(described_class.weight_for("definitely")).to be > 0.8
  end

  it "returns nil for a lemma it knows nothing about" do
    expect(described_class.weight_for("database")).to be_nil
  end

  it "is case-insensitive" do
    expect(described_class.weight_for("Might")).to eq(described_class.weight_for("might"))
  end

  it "keeps every weight inside the ModalityWeight range" do
    all = described_class::MODALS.values + described_class::HEDGES.values + described_class::BOOSTERS.values

    expect(all).to all(be_between(0.0, 1.0))
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/annotation/modality_lexicon_spec.rb`
Expected: FAIL — `uninitialized constant SFL::Annotation::ModalityLexicon`

- [ ] **Step 3: Write the implementation**

```ruby
# lib/sfl/annotation/modality_lexicon.rb
# frozen_string_literal: true

module SFL
  module Annotation
    # Lemma -> modality weight, on Types::ModalityWeight's 0.0..1.0 scale
    # where low is tentative and high is categorical.
    #
    # Split out from RulesAnnotator so the linguistic data can be reviewed
    # and tuned without touching traversal logic — this table is the part
    # most likely to change once it has met real vault text.
    #
    # These are starting values, not measurements. They are ordered by the
    # relative strength SFL's modality cline describes (possibility <
    # probability < certainty; permission < obligation), but the exact
    # numbers want calibrating against real output before anything downstream
    # treats a specific threshold as meaningful.
    module ModalityLexicon
      extend self

      # Modal auxiliaries — the primary carrier of modality in English.
      MODALS = {
        "might" => 0.2, "may" => 0.25, "could" => 0.25, "can" => 0.4,
        "should" => 0.6, "would" => 0.5, "ought" => 0.6,
        "will" => 0.8, "shall" => 0.8, "must" => 0.95,
      }.freeze

      # Lexical hedges — downgrade the speaker's commitment.
      HEDGES = {
        "possibly" => 0.2, "perhaps" => 0.2, "maybe" => 0.2,
        "seem" => 0.3, "appear" => 0.3, "suggest" => 0.35,
        "somewhat" => 0.35, "arguably" => 0.3, "apparently" => 0.3,
      }.freeze

      # Lexical boosters — upgrade it.
      BOOSTERS = {
        "definitely" => 0.9, "certainly" => 0.9, "clearly" => 0.85,
        "obviously" => 0.85, "always" => 0.9, "never" => 0.9,
        "undoubtedly" => 0.95, "must" => 0.95,
      }.freeze

      # Merged lookup. MODALS is applied last so a lemma appearing in two
      # tables ("must") resolves to its modal reading, which is the one the
      # dependency parse will have tagged it as.
      TABLE = HEDGES.merge(BOOSTERS).merge(MODALS).freeze

      # @param lemma [String]
      # @return [Float, nil] nil when the lemma carries no modality signal
      def weight_for(lemma) = TABLE[lemma.to_s.downcase]
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/annotation/modality_lexicon_spec.rb`
Expected: PASS (7 examples, 0 failures)

- [ ] **Step 5: Verify Zeitwerk and RuboCop**

Run: `bundle exec rspec spec/zeitwerk_spec.rb && bundle exec rubocop lib/sfl/annotation spec/annotation`
Expected: both PASS/clean

- [ ] **Step 6: Commit**

```bash
git add lib/sfl/annotation/modality_lexicon.rb spec/annotation/modality_lexicon_spec.rb
git commit -m "✨ feat(annotation): add modality lexicon of modals, hedges and boosters"
```

---

### Task 5: `Annotation::RulesAnnotator`

**Files:**
- Create: `lib/sfl/annotation/rules_annotator.rb`
- Test: `spec/annotation/rules_annotator_spec.rb`

**Interfaces:**
- Consumes: `SFL::Annotation::ModalityLexicon` (Task 4); `SFL::Core::Types::SyntacticClause`, `SyntacticToken`, `InterpersonalPayload`, `MoodType`
- Produces: `SFL::Annotation::RulesAnnotator.new.annotate(syntactic_clause) -> SFL::Core::Types::InterpersonalPayload` with `annotation_source: "rules"`

**Before writing anything, read `lib/sfl/core/types/interpersonal_payload.rb` and `lib/sfl/core/types/mood_type.rb`** and use their exact attribute names and mood values. The code below assumes `mood`, `modality_weight`, `tenor`, `speaker_attitude`, `annotation_source` and a `MoodType` with declarative/interrogative/imperative members — if the real types differ, follow the real types and adjust the spec.

**`tenor` and `speaker_attitude` are left at whatever the type requires as a default and are never derived.** If `InterpersonalPayload` requires a non-nil `tenor`, pass the type's own default and assert in the spec that `trusted_for?("rules", :tenor)` is `false` — the predicate, not the value, is what marks it underived.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/annotation/rules_annotator_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Annotation::RulesAnnotator do
  # Minimal token builder — only the fields the annotator reads.
  def token(text, lemma: nil, pos: "VERB", tag: "VB", dep: "ROOT", index: 0, head_index: -1)
    SFL::Core::Types::SyntacticToken.new(
      text:, lemma: lemma || text.downcase, pos:, tag:, dep:, head_index:, index:, morphology: {}
    )
  end

  def clause(tokens, text: tokens.map(&:text).join(" "))
    SFL::Core::Types::SyntacticClause.new(
      text:, tokens:, groups: [], sentence_index: 0, root_index: 0
    )
  end

  subject(:annotator) { described_class.new }

  describe "modality" do
    it "reads a tentative modal as low modality" do
      result = annotator.annotate(clause([
        token("This", pos: "PRON", tag: "DT", dep: "nsubj", index: 0),
        token("might", pos: "AUX", tag: "MD", dep: "aux", index: 1),
        token("cause", index: 2),
      ]))

      expect(result.modality_weight).to be < 0.4
    end

    it "reads a categorical modal as high modality" do
      result = annotator.annotate(clause([
        token("This", pos: "PRON", tag: "DT", dep: "nsubj", index: 0),
        token("must", pos: "AUX", tag: "MD", dep: "aux", index: 1),
        token("cause", index: 2),
      ]))

      expect(result.modality_weight).to be > 0.8
    end

    it "reads a bare assertion as high modality, since an unhedged claim is categorical" do
      result = annotator.annotate(clause([
        token("This", pos: "PRON", tag: "DT", dep: "nsubj", index: 0),
        token("causes", index: 1),
        token("latency", pos: "NOUN", tag: "NN", dep: "dobj", index: 2),
      ]))

      expect(result.modality_weight).to be > 0.7
    end

    it "picks the lowest signal when a clause both hedges and boosts" do
      result = annotator.annotate(clause([
        token("This", pos: "PRON", tag: "DT", dep: "nsubj", index: 0),
        token("could", pos: "AUX", tag: "MD", dep: "aux", index: 1),
        token("definitely", pos: "ADV", tag: "RB", dep: "advmod", index: 2),
        token("work", index: 3),
      ]))

      expect(result.modality_weight).to be < 0.4
    end
  end

  describe "mood" do
    it "reads a statement as declarative" do
      result = annotator.annotate(clause([token("It", pos: "PRON", dep: "nsubj"), token("works", index: 1)]))

      expect(result.mood.to_s).to match(/declarative/i)
    end

    it "reads a question mark as interrogative" do
      result = annotator.annotate(clause(
        [token("It", pos: "PRON", dep: "nsubj"), token("works", index: 1)],
        text: "Does it work?"
      ))

      expect(result.mood.to_s).to match(/interrogative/i)
    end

    it "reads a bare-infinitive root with no subject as imperative" do
      result = annotator.annotate(clause([token("Run", tag: "VB", dep: "ROOT")], text: "Run the migration"))

      expect(result.mood.to_s).to match(/imperative/i)
    end
  end

  describe "provenance" do
    it "marks every annotation as rules-derived" do
      result = annotator.annotate(clause([token("It", pos: "PRON", dep: "nsubj"), token("works", index: 1)]))

      expect(result.annotation_source).to eq("rules")
    end

    it "is not trusted for tenor, which it never derives" do
      expect(SFL::Core::Types.trusted_for?("rules", :tenor)).to be(false)
    end

    it "is trusted for the two fields it does derive" do
      expect(SFL::Core::Types.trusted_for?("rules", :mood)).to be(true)
      expect(SFL::Core::Types.trusted_for?("rules", :modality_weight)).to be(true)
    end
  end

  it "never raises on an empty clause" do
    expect { annotator.annotate(clause([], text: "")) }.not_to raise_error
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/annotation/rules_annotator_spec.rb`
Expected: FAIL — `uninitialized constant SFL::Annotation::RulesAnnotator`

- [ ] **Step 3: Write the implementation**

```ruby
# lib/sfl/annotation/rules_annotator.rb
# frozen_string_literal: true

module SFL
  module Annotation
    # Derives the interpersonal payload from Pass 1 syntax, with no LLM.
    #
    # This is the DEFAULT annotation path. Pass 2 (LLM) becomes opt-in, used
    # to produce gold annotations for fine-tuning rather than to run the
    # system — so no default path needs an API key and a full re-sweep of the
    # corpus is free.
    #
    # Only mood and modality_weight are derived, because only those two are
    # deterministically recoverable from a dependency parse. Tenor and
    # speaker attitude are NOT guessed: a fabricated value is worse than an
    # absent one, which is the lesson CorrelationAnalyzer already encodes
    # when it reports nil rather than a 0.5 midpoint. Types.trusted_for?
    # is what tells downstream consumers which fields this source backs.
    class RulesAnnotator
      # An unhedged assertion is a categorical claim, so the absence of any
      # modal or hedge is itself a high-modality signal — not a missing
      # measurement. "This causes latency" commits harder than "this might".
      BARE_ASSERTION_WEIGHT = 0.8

      MODAL_TAG = "MD"
      BARE_INFINITIVE_TAG = "VB"
      SUBJECT_DEPS = %w[nsubj nsubjpass csubj expl].freeze

      # @param clause [Core::Types::SyntacticClause]
      # @return [Core::Types::InterpersonalPayload]
      def annotate(clause)
        Core::Types::InterpersonalPayload.new(
          mood: mood_for(clause),
          modality_weight: modality_for(clause),
          annotation_source: "rules"
        )
      end

      # The LOWEST signal wins. Modality is a commitment ceiling: a speaker
      # who says "could definitely work" has still only committed to "could",
      # and averaging the two would report a confidence they never expressed.
      private def modality_for(clause)
        weights = clause.tokens.filter_map { |t| ModalityLexicon.weight_for(t.lemma) }
        return BARE_ASSERTION_WEIGHT if weights.empty?

        weights.min
      end

      private def mood_for(clause)
        return Core::Types::MoodType::Interrogative if interrogative?(clause)
        return Core::Types::MoodType::Imperative if imperative?(clause)

        Core::Types::MoodType::Declarative
      end

      private def interrogative?(clause)
        clause.text.to_s.strip.end_with?("?") || subject_after_modal?(clause)
      end

      # Auxiliary inversion: "Does it work" puts the modal/aux before the
      # subject, which a question mark alone would miss in transcribed speech.
      private def subject_after_modal?(clause)
        modal = clause.tokens.find { |t| t.tag == MODAL_TAG }
        subject = clause.tokens.find { |t| SUBJECT_DEPS.include?(t.dep) }
        return false if modal.nil? || subject.nil?

        modal.index < subject.index
      end

      # A bare-infinitive root with no subject at all: "Run the migration".
      private def imperative?(clause)
        root = clause.tokens.find { |t| t.dep == "ROOT" } || clause.tokens.first
        return false if root.nil?

        root.tag == BARE_INFINITIVE_TAG && clause.tokens.none? { |t| SUBJECT_DEPS.include?(t.dep) }
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/annotation/rules_annotator_spec.rb`
Expected: PASS (11 examples, 0 failures)

If `InterpersonalPayload` requires `tenor` or `speaker_attitude` to be present, pass the type's own documented default rather than inventing one, and leave the trust predicate as the marker that the field is underived.

If `MoodType` members are named differently (e.g. lowercase strings rather than constants), follow the real type.

- [ ] **Step 5: Verify Zeitwerk and RuboCop**

Run: `bundle exec rspec spec/zeitwerk_spec.rb && bundle exec rubocop lib/sfl/annotation spec/annotation`
Expected: both PASS/clean

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rspec`
Expected: green

- [ ] **Step 7: Commit**

```bash
git add lib/sfl/annotation/rules_annotator.rb spec/annotation/rules_annotator_spec.rb
git commit -m "✨ feat(annotation): derive mood and modality from syntax without an LLM"
```

---

## Self-Review Notes

**Spec coverage.** This plan covers pairing (Tasks 1–2) and rules-based annotation with provenance (Tasks 3–5). Deliberately **not** covered, each needing its own plan: media ingest (`2026-08-31-media-ingest-and-onboarding-design.md` — audio, video, dispatch wiring, onboarding wizard), the `Nexo::Workflow` wrapper, the `contradictions` table and NLI detection, dataset export, and BERTopic gaps.

**Deferred deliberately.** `AttachmentSet` currently holds one attachment per set. The spec describes a parent note with *multiple* attachments; grouping is a natural fit for the workflow wrapper, where the batch has all sets in hand. Task 1's type already accepts an array, so grouping is a caller change, not a type change.

**Calibration, not assertion.** Task 2's smoke test and the `ModalityLexicon` weights are explicitly starting values to be measured against the real vault. No task asserts a specific threshold is correct — only that the relative ordering holds.
