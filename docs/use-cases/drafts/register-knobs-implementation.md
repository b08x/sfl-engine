# SFL Register Knobs: Implementation Entry Points

**Purpose**: Document the integration points for implementing register-knob-based synthetic scenario generation in the SFL Engine.

**Status**: Draft — TUI integration design complete (§10).

---

## 1. Architecture Overview

The register knobs feature adds **controlled synthetic text generation** to balance the SFL metafunction distribution in the training corpus. The core problem: synthetic worklogs are 86% material-process heavy, while real worklogs are 77% verbal-process heavy. The knobs control input generation *before* Pass 1 ingestion, not Pass 2 annotation.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Register Knob System                         │
├─────────────────────────────────────────────────────────────────┤
│  ScenarioGenerator  →  ScenarioValidator  →  scenarios.yaml    │
│       (Ruby)              (spaCy)            (fixture)         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Existing Pipeline                            │
├─────────────────────────────────────────────────────────────────┤
│  CLI#build_pipeline  →  Pipeline#compile  →  Pass1::Engine     │
│       (wiring)             (orchestration)     (spaCy parse)   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. New Files

```
lib/sfl/
├── cli/
│   ├── scenario_tui.rb          # TTY::Prompt-based interactive workflow
│   └── scenario_options.rb      # Option parsing for --ci-pool, --count, --dry-run
├── core/
│   └── pass_one/
│       ├── scenario_generator.rb    # Knob sampling, ERB template rendering
│       ├── scenario_validator.rb    # spaCy-based validation of generated text
│       ├── templates/
│       │   ├── symptom.erb          # ERB template for ticket symptoms
│       │   ├── worklog.erb          # ERB template for analyst worklog entries
│       │   └── resolution.erb       # ERB template for resolution notes
│       └── fixtures/
│           └── scenarios.yaml       # Reviewed, versioned synthetic scenarios
```

| File | Class | Purpose |
|------|-------|---------|
| `lib/sfl/cli/scenario_tui.rb` | `SFL::CLI::ScenarioTUI` | TTY::Prompt-based interactive workflow |
| `lib/sfl/cli/scenario_options.rb` | `SFL::CLI::ScenarioOptions` | Option parsing for `--ci-pool`, `--count`, `--dry-run` |
| `lib/sfl/core/pass_one/scenario_generator.rb` | `SFL::Core::PassOne::ScenarioGenerator` | Knob sampling, ERB template rendering |
| `lib/sfl/core/pass_one/scenario_validator.rb` | `SFL::Core::PassOne::ScenarioValidator` | spaCy-based validation of generated text |
| `lib/sfl/core/pass_one/templates/symptom.erb` | — | ERB template for ticket symptoms |
| `lib/sfl/core/pass_one/templates/worklog.erb` | — | ERB template for analyst worklog entries |
| `lib/sfl/core/pass_one/templates/resolution.erb` | — | ERB template for resolution notes |
| `lib/sfl/core/pass_one/fixtures/scenarios.yaml` | — | Reviewed, versioned synthetic scenarios |

---

## 3. Existing Integration Points

### 3.1 Pipeline Entry

**File**: `lib/sfl/core/pipeline.rb`

**Method**: `Pipeline#compile` (line 81)

```ruby
def compile(text, document_id: nil, store: true, embed: true, resume: false,
            semantic_coherence_score: nil, pass_one_only: false)
```

**Change needed**: Add `source: :real` parameter.

```ruby
def compile(text, document_id: nil, store: true, embed: true, resume: false,
            semantic_coherence_score: nil, pass_one_only: false, source: :real, 
            register_metadata: {})
```

- `source:` — `:real` or `:synthetic`
- `register_metadata:` — knob values for provenance tracking (only populated when `source: :synthetic`)

### 3.2 Pass 1 Entry

**File**: `lib/sfl/core/pass_one/spacy_sidecar_parser.rb`

**Method**: `SpacySidecarParser#parse` (line 40)

```ruby
def parse(text, document_id: nil)
  @mutex.synchronize { request(text, document_id) }
end
```

**No changes needed** — this is the validation entry point. `ScenarioValidator` calls this to verify generated text produces valid clause structure.

### 3.3 CLI Wiring

**File**: `lib/sfl/cli.rb`

**Method**: `CLI#build_pipeline` (line 457)

```ruby
module_function def build_pipeline(boot_result, options, breaker:, instrumenter:, logger:)
  parser = Core::PassOne::SpacySidecarParser.new(model: boot_result.spacy_model,
    command: boot_result.pass1_command, env: boot_result.pass1_env || {}, logger:)
  pass_one = Core::PassOne::Engine.new(parser:, instrumenter:, logger:)
  # ...
  Core::Pipeline.new(pass_one:, pass_two:, ...)
end
```

**Change needed**: Accept and forward `source:` and `register_metadata:` options.

### 3.4 Ingest Orchestrator

**File**: `lib/sfl/ingest/orchestrator.rb`

**Method**: `Orchestrator#run` (line 48)

```ruby
def run(path)
  counts = { dispatched: 0, review_entries: 0, drafted: 0 }
  files(path).each { |file| process(file, counts) }
  logger.info { "ingest run complete: #{counts}" }
  counts
end
```

**Change needed**: Add synthetic source detection — if file is in `fixtures/scenarios.yaml`, pass `source: :synthetic`.

---

## 4. Knob Definitions

**Location**: `lib/sfl/core/pass_one/scenario_generator.rb`

```ruby
module SFL
  module Core
    module PassOne
      PROCESS_MIX = %i[material_only material_verbal verbal_dominant].freeze
      PARTICIPANTS = %i[solo pair escalated multi_team].freeze
      MODALITY = %i[categorical hedged uncertain].freeze
      EPISODES = %i[single two_entry multi_entry].freeze
      SPAN = %i[same_hour same_day multi_day].freeze
      REGISTER = %i[clean hurried fragmented].freeze
      
      # Sampling weights derived from real corpus measurements
      WEIGHTS = {
        process_mix: { material_only: 0.23, material_verbal: 0.54, verbal_dominant: 0.23 },
        participants: { solo: 0.23, pair: 0.30, escalated: 0.30, multi_team: 0.17 },
        modality: { categorical: 0.69, hedged: 0.23, uncertain: 0.08 },
        episodes: { single: 0.49, two_entry: 0.31, multi_entry: 0.20 },
        span: { same_hour: 0.40, same_day: 0.46, multi_day: 0.14 },
        register: { clean: 0.66, hurried: 0.23, fragmented: 0.11 },
      }.freeze
    end
  end
end
```

---

## 5. Validation Rules

**File**: `lib/sfl/core/pass_one/scenario_validator.rb`

**Incoherent knob combinations** (reject before generation):

| Constraint | Reason |
|------------|--------|
| `span=multi_day` requires `episodes != single` | Multi-day span with single episode is contradictory |
| `participants=solo` forbids `process_mix=verbal_dominant` | Verbal processes require multiple participants |
| `episodes=multi_entry` requires `span != same_hour` | Multiple entries cannot fit in one hour |

**Output validation** (after spaCy parsing):

| Check | Target |
|-------|--------|
| Verbal process density | 0-10% (material_only), 30-60% (material_verbal), 60-100% (verbal_dominant) |
| Participant count | Matches `participants` knob |
| Episode count | Matches `episodes` knob |
| Clause validity | All clauses parse without error |

---

## 6. Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    TUI (sfl scenario generate)                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Select CI    │→ │ Select Knobs │→ │ Preview &    │          │
│  │ Pool         │  │ (auto/manual)│  │ Validate     │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Register Knob System                         │
├─────────────────────────────────────────────────────────────────┤
│  ScenarioGenerator  →  ScenarioValidator  →  scenarios.yaml    │
│       (Ruby)              (spaCy)            (fixture)         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Existing Pipeline                            │
├─────────────────────────────────────────────────────────────────┤
│  CLI#build_pipeline → Pipeline#compile(source: :synthetic)       │
│       │                    │                                     │
│       ▼                    ▼                                     │
│  PassOne::Engine    IdeationalExtractor                         │
│       │                    │                                     │
│       ▼                    ▼                                     │
│  SpacySidecarParser  LLM::Engine (Pass 2)                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## 7. Provenance Tracking

Every synthetic clause must carry metadata for audit:

```ruby
# In AnnotatedClause (lib/sfl/core/types/annotated_clause.rb)
{
  id: "uuid",
  text: "posted to vendor regarding outage",
  source: :synthetic,                    # NEW
  register_metadata: {                   # NEW
    process_mix: :verbal_dominant,
    participants: :escalated,
    modality: :hedged,
    episodes: :two_entry,
    span: :same_day,
    register: :hurried,
    ci_pool: "Synapse",
    generated_at: "2026-08-12T10:00:00Z"
  },
  # ... existing fields ...
}
```

---

## 8. Testing Strategy

| Test | File | Purpose |
|------|------|---------|
| Unit: knob sampling | `spec/lib/sfl/core/pass_one/scenario_generator_spec.rb` | Verify coherent sampling |
| Unit: incoherent rejection | `spec/lib/sfl/core/pass_one/scenario_validator_spec.rb` | Verify constraint enforcement |
| Integration: pipeline with synthetic source | `spec/lib/sfl/core/pipeline_spec.rb` | Verify `source: :synthetic` flows through |
| E2E: knob distribution | `spec/integration/register_knobs_spec.rb` | Verify output matches target weights |

---

## 9. Implementation Order

1. **Create `ScenarioGenerator`** — knob sampling, ERB rendering
2. **Create `ScenarioValidator`** — spaCy validation, constraint checking
3. **Generate 10 scenarios** — focus on `verbal_dominant`, `escalated`, `multi_entry`
4. **Add `source:` parameter to Pipeline** — provenance tracking
5. **Integrate with CLI** — `--source synthetic` flag
6. **Add TUI** — interactive knob selection (see §10)

---

## 10. TUI Integration

### 10.1 Design Decision: Standalone TUI

**Chosen approach**: Option A — standalone `sfl scenario generate` subcommand.

**Rationale**:
- Scenario generation is an **offline authoring task**, not a runtime operation
- Clean separation from the ingest pipeline (generation → review → commit → ingest)
- Leverages existing `tty-prompt` gem (already in Gemfile)
- Testable independently of the pipeline
- Follows the pattern in `docs/use-cases/drafts/sfl-register-knobs-ruby-variant.md` §5: "Generation happens **outside** the main pipeline"

### 10.2 CLI Integration Point

**File**: `lib/sfl/cli.rb`

**Current subcommand list** (line 95):
```ruby
unless %i[conversation documentation knowledge_base ingest context].include?(command)
  raise UsageError, "Unknown subcommand: #{command}\n\n#{USAGE}"
end
```

**Change needed**: Add `:scenario` to the allowed subcommands.

```ruby
unless %i[conversation documentation knowledge_base ingest context scenario].include?(command)
  raise UsageError, "Unknown subcommand: #{command}\n\n#{USAGE}"
end
```

**New usage block** (add to USAGE constant):
```
scenario                      Interactive TUI for generating synthetic scenarios
                              with register knobs — review knobs, preview output,
                              validate with spaCy, commit to scenarios.yaml
```

### 10.3 New Files for TUI

| File | Class | Purpose |
|------|-------|---------|
| `lib/sfl/cli/scenario_tui.rb` | `SFL::CLI::ScenarioTUI` | TTY::Prompt-based interactive workflow |
| `lib/sfl/cli/scenario_options.rb` | `SFL::CLI::ScenarioOptions` | Option parsing for `--ci-pool`, `--count`, `--dry-run` |

### 10.4 TUI Workflow

```
$ sfl scenario generate

? Select CI pool: (Use arrow keys)
  ❯ Synapse
    EPIC
    PowerScribe
    RadAssist
    Fluency

? Number of scenarios to generate: 10

? Select knob mode: (Use arrow keys)
  ❯ Auto-sample (weighted distribution)
    Manual (select each knob)
    Fill gaps (target underrepresented cells)

┌─────────────────────────────────────────────────────────────────┐
│ Register Coverage (current → target)                           │
├─────────────────────────────────────────────────────────────────┤
│ process_mix:    material_only    80% → 23%  ████████░░░░░░░░  │
│                 material_verbal  18% → 54%  ███░░░░░░░░░░░░░  │
│                 verbal_dominant   2% → 23%  ░░░░░░░░░░░░░░░░  │
│ participants:   solo             70% → 23%  ██████████████░░  │
│                 escalated        10% → 30%  ██░░░░░░░░░░░░░░  │
│                 multi_team        0% → 17%  ░░░░░░░░░░░░░░░░  │
└─────────────────────────────────────────────────────────────────┘

? Generate scenarios? Yes

Generating 10 scenarios...
  ✓ verbal_dominant + escalated + multi_entry (validated)
  ✓ verbal_dominant + multi_team + two_entry (validated)
  ✓ material_verbal + escalated + multi_entry (validated)
  ...

┌─────────────────────────────────────────────────────────────────┐
│ Generated Scenarios (10)                                        │
├─────────────────────────────────────────────────────────────────┤
│ 1. [verbal_dominant] INC0089234 - Synapse frozen...            │
│ 2. [verbal_dominant] INC0089235 - EPIC login timeout...        │
│ 3. [material_verbal] INC0089236 - PowerScribe crash...         │
│ ...                                                             │
└─────────────────────────────────────────────────────────────────┘

? Review scenarios: (Select all that apply)
  ❯ [x] 1. INC0089234 - verbal_dominant
  ❯ [x] 2. INC0089235 - verbal_dominant
  ❯ [x] 3. INC0089236 - material_verbal
  [ ] 4. INC0089237 - material_verbal (skip)

? Commit to scenarios.yaml? Yes

Written 9 scenarios to lib/sfl/core/pass_one/fixtures/scenarios.yaml
Register coverage updated: verbal_dominant 2% → 21%
```

### 10.5 TUI Class Structure

**File**: `lib/sfl/cli/scenario_tui.rb`

```ruby
# frozen_string_literal: true

require "tty-prompt"

module SFL
  module CLI
    # Interactive TUI for register-knob scenario generation.
    # Uses tty-prompt for selection menus, progress display, and confirmation.
    # Runs offline — never touches the main pipeline.
    class ScenarioTUI
      def initialize(prompt: TTY::Prompt.new, generator: nil, validator: nil)
        @prompt = prompt
        @generator = generator || Core::PassOne::ScenarioGenerator.new
        @validator = validator || Core::PassOne::ScenarioValidator.new
      end

      # Main entry point — runs the full interactive workflow.
      # @return [Hash] { committed: Integer, skipped: Integer }
      def run
        ci_pool = select_ci_pool
        count = select_count
        mode = select_mode
        
        knobs = case mode
                when :auto then auto_sample(ci_pool, count)
                when :manual then manual_select(count)
                when :fill_gaps then fill_gaps(ci_pool, count)
                end
        
        scenarios = generate_and_validate(knobs)
        reviewed = review_scenarios(scenarios)
        commit(reviewed)
      end

      private

      def select_ci_pool
        @prompt.select("Select CI pool:") do |menu|
          menu.choice "Synapse", "Synapse"
          menu.choice "EPIC", "EPIC"
          menu.choice "PowerScribe", "PowerScribe"
          menu.choice "RadAssist", "RadAssist"
          menu.choice "Fluency", "Fluency"
        end
      end

      def select_count
        @prompt.slider("Number of scenarios:", min: 1, max: 50, default: 10)
      end

      def select_mode
        @prompt.select("Knob selection mode:") do |menu|
          menu.choice "Auto-sample (weighted distribution)", :auto
          menu.choice "Manual (select each knob)", :manual
          menu.choice "Fill gaps (target underrepresented cells)", :fill_gaps
        end
      end

      def auto_sample(ci_pool, count)
        count.times.map { @generator.sample_knobs(ci_pool) }
      end

      def manual_select(count)
        count.times.map do |i|
          @prompt.say("\nScenario #{i + 1}:")
          {
            process_mix: @prompt.select("  Process mix:") { |m|
              m.choice "material_only", :material_only
              m.choice "material_verbal", :material_verbal
              m.choice "verbal_dominant", :verbal_dominant
            },
            participants: @prompt.select("  Participants:") { |m|
              m.choice "solo", :solo
              m.choice "pair", :pair
              m.choice "escalated", :escalated
              m.choice "multi_team", :multi_team
            },
            # ... other knobs ...
          }
        end
      end

      def fill_gaps(ci_pool, count)
        coverage = load_coverage(ci_pool)
        cells = @generator.underweighted_cells(coverage)
        cells.sample(count).map { |cell| @generator.sample_knobs(ci_pool, fixed: cell) }
      end

      def generate_and_validate(knobs_list)
        @prompt.progress_bar("Generating scenarios") do |bar|
          knobs_list.each_with_index.map do |knobs, i|
            text = @generator.generate(:worklog, ci_pool: knobs[:ci_pool], **knobs)
            result = @validator.validate_worklog(text, knobs)
            bar.update(i + 1)
            { knobs:, text:, valid: result[:valid], violations: result[:violations] }
          end
        end
      end

      def review_scenarios(scenarios)
        valid = scenarios.select { |s| s[:valid] }
        @prompt.say("\n#{valid.size}/#{scenarios.size} scenarios passed validation")
        
        @prompt.multi_select("Select scenarios to commit:") do |menu|
          valid.each_with_index do |s, i|
            menu.choice "[#{s[:knobs][:process_mix]}] #{s[:text][0..60]}...", i
          end
        end.map { |i| valid[i] }
      end

      def commit(reviewed)
        path = "lib/sfl/core/pass_one/fixtures/scenarios.yaml"
        # ... append to YAML, update coverage ...
        @prompt.ok("Written #{reviewed.size} scenarios to #{path}")
      end

      def load_coverage(ci_pool)
        # Load existing coverage from scenarios.yaml
        {}
      end
    end
  end
end
```

### 10.6 CLI Wiring

**File**: `lib/sfl/cli.rb`

**New method** (add after `run_context`):
```ruby
module_function def run_scenario(options)
  require_relative "cli/scenario_tui"
  
  if options[:dry_run]
    # Just show what would be generated
    generator = Core::PassOne::ScenarioGenerator.new
    scenarios = options[:count].times.map { generator.sample_knobs(options[:ci_pool]) }
    puts JSON.pretty_generate(scenarios)
  else
    tui = ScenarioTUI.new
    tui.run
  end
end
```

**New parser** (add after `parse_context_options`):
```ruby
module_function def parse_scenario_options(argv)
  options = { count: 10, ci_pool: nil, dry_run: false }
  
  OptionParser.new do |opt|
    opt.on("--count N", Integer, "Number of scenarios") { |v| options[:count] = v }
    opt.on("--ci-pool POOL", "CI pool name") { |v| options[:ci_pool] = v }
    opt.on("--dry-run", "Print generated knobs without writing") { options[:dry_run] = true }
  end.parse!(argv)
  
  options
end
```

**Update `run` method** (line 210):
```ruby
module_function def run(argv)
  # ... existing parse logic ...
  case command
  # ... existing commands ...
  when :scenario then run_scenario(options)
  end
end
```

### 10.7 Coverage Display

The TUI shows current register coverage vs target distribution. This requires:

**New method** in `ScenarioGenerator`:
```ruby
def coverage_report(ci_pool)
  scenarios = load_existing(ci_pool)
  {
    process_mix: compute_distribution(scenarios, :process_mix),
    participants: compute_distribution(scenarios, :participants),
    # ...
  }
end
```

**Visual format** (using `tty-progressbar`):
```
process_mix:    material_only    80% → 23%  ████████░░░░░░░░
                material_verbal  18% → 54%  ███░░░░░░░░░░░░░
                verbal_dominant   2% → 23%  ░░░░░░░░░░░░░░░░
```

### 10.8 Dry-Run Mode

For CI/automation, `--dry-run` outputs JSON without interactive prompts:

```bash
$ sfl scenario generate --ci-pool Synapse --count 5 --dry-run
[
  {"process_mix": "verbal_dominant", "participants": "escalated", "modality": "hedged", "episodes": "multi_entry", "span": "same_day", "register": "hurried"},
  {"process_mix": "verbal_dominant", "participants": "multi_team", "modality": "categorical", "episodes": "two_entry", "span": "same_day", "register": "clean"},
  ...
]
```

### 10.9 Integration with Existing Commands

The TUI does **not** modify `sfl ingest`. The workflow is:

```
sfl scenario generate     # TUI: select knobs, preview, commit
      ↓
scenarios.yaml            # reviewed fixture
      ↓
sfl ingest <path>         # existing pipeline, no changes
```

This keeps the separation of concerns clean:
- **Generation** = offline authoring (TUI)
- **Ingestion** = runtime processing (pipeline)

### 10.10 Implementation Order (Updated)

1. Create `ScenarioGenerator` — knob sampling, ERB rendering
2. Create `ScenarioValidator` — spaCy validation
3. Create `ScenarioTUI` — interactive workflow with tty-prompt
4. Add `scenario` subcommand to CLI
5. Generate 10 scenarios via TUI
6. Add `source:` parameter to Pipeline
7. Integrate with ingest (detect synthetic sources)

---

*Sources: `docs/use-cases/drafts/sfl-register-knobs-ruby-variant.md`, `lib/sfl/core/pipeline.rb`, `lib/sfl/cli.rb`, `lib/sfl/core/pass_one/spacy_sidecar_parser.rb`*
