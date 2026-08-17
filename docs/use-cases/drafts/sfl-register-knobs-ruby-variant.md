# SFL Register Knobs for Pass 1 Scenario Generation

**Project Context**: SFL Engine (Ruby), Pass 1 spaCy sidecar, offline scenario
authoring for synthetic incident corpus. Target: `lib/sfl/core/pass1/sidecar.rb`
integration path.

**Key Difference from DSPy Variant**: This document adapts the register knob pattern
to the SFL Engine's two-pass architecture where Pass 1 (spaCy Python subprocess)
generates clause-level annotations, and Pass 2 (ruby_llm) performs semantic
annotation. The knobs here control *input generation* for Pass 1, not LM prompting.

---

## 1. The gap, remeasured in SFL Engine terms

The original finding stands: synthetic worklogs are **material-process heavy**,
real worklogs are **verbal-process heavy**. In SFL Engine terms:

| SFL Metafunction | Signal Type | % REAL | % SYN | Pass 1 Relevance |
|-----------------|-------------|-------|-------|------------------|
| **Ideational** | Verbal process verbs | **77%** | **6%** | `verb` + `dep_` features |
| **Ideational** | Material process verbs | 63% | **86%** | `verb` + `dep_` features |
| **Interpersonal** | Modality/hedging | **31%** | **6%** | `aux` + `advmod` features |
| **Textual** | Multi-entry structure | **51%** | **0%** | Sentence boundary detection |
| **Textual** | Multi-date span | **14%** | **0%** | Temporal adverbial extraction |

**Critical for SFL Engine**: The verbal/process imbalance directly affects
Pass 1's ability to extract **stance-separated content**. Verbal processes
(`called`, `informed`, `pinged`) carry interpersonal stance. Material processes
(`restarted`, `reinstalled`) carry ideational content. The 77% vs 6% gap means
Pass 1 receives predominantly ideational input, limiting stance-filtering effectiveness.

---

## 2. Why SFL Engine needs these knobs (not just DSPy)

The three metafunctions map to **three extraction failures** in Pass 1:

| Metafunction | Register Variable | Extraction Failure | SFL Engine Impact |
|--------------|-------------------|-------------------|-------------------|
| **Ideational** | Field | Missing verbal process tokens | Stance layer under-populated |
| **Interpersonal** | Tenor | Single participant, no hedging | Tenor analysis returns flat profiles |
| **Textual** | Mode | Single monologue block | Mode detection defaults to `monologue` |

**Architectural constraint**: Pass 1 cannot fix what isn't in the text.
The sidecar's `extract_clauses` method in `lib/sfl/core/pass1/extractor.py`
relies on spaCy's dependency parse. If the input text lacks verbal process
verbs, no amount of NLP sophistication extracts them.

**Therefore**: The knobs must control **synthetic text generation** *before*
Pass 1 ingestion, not Pass 2 annotation.

---

## 3. The knobs (Ruby-compatible enum definitions)

Six parameters, defined as Ruby symbols for interoperability with the
spaCy sidecar's JSON bridge:

```ruby
# lib/sfl/core/pass1/scenario_generator.rb
module SFL
  module Core
    module Pass1
      PROCESS_MIX = %i[material_only material_verbal verbal_dominant].freeze
      PARTICIPANTS = %i[solo pair escalated multi_team].freeze
      MODALITY = %i[categorical hedged uncertain].freeze
      EPISODES = %i[single two_entry multi_entry].freeze
      SPAN = %i[same_hour same_day multi_day].freeze
      REGISTER = %i[clean hurried fragmented].freeze
    end
  end
end
```

**Sampling weights** (identical to DSPy variant, derived from real corpus):

| Knob | Distribution | Source |
|---|---|---|
| `process_mix` | `{material_only: 0.23, material_verbal: 0.54, verbal_dominant: 0.23}` | 77% REAL carry ≥1 verbal |
| `participants` | `{solo: 0.23, pair: 0.30, escalated: 0.30, multi_team: 0.17}` | median 8 distinct parties |
| `modality` | `{categorical: 0.69, hedged: 0.23, uncertain: 0.08}` | 31% REAL hedge |
| `episodes` | `{single: 0.49, two_entry: 0.31, multi_entry: 0.20}` | 18/35 ≥2 entries |
| `span` | `{same_hour: 0.40, same_day: 0.46, multi_day: 0.14}` | 5/35 ≥2 dates |
| `register` | `{clean: 0.66, hurried: 0.23, fragmented: 0.11}` | 11% typo markers |

---

## 4. The generation chain (Ruby + spaCy sidecar)

Unlike the DSPy variant which uses LM chaining, SFL Engine's Pass 1 uses
a **template-based generator** with spaCy validation:

```
       YAML templates + register knobs
                │
         ┌──────▼───────┐
         │   Symptom    │   ERB template, spaCy token validation
         └──────┬───────┘
                │ JSON
         ┌──────▼───────┐
         │ spaCy Sidecar │   validate tokens, dependency parse
         └──────┬───────┘
                │ validated text
         ┌──────▼───────┐
         │   Worklog    │   ERB template, all six knobs
         └──────┬───────┘
                │ JSON
         ┌──────▼───────┐
         │ spaCy Sidecar │   extract clauses, validate structure
         └──────┬───────┘
                │ annotated clauses
         ┌──────▼───────┐
         │  Resolution  │   ERB template, action consistency check
         └──────┬───────┘
                │
         Pass 1 output → Pass 2 input
```

**Template example** (`lib/sfl/core/pass1/templates/worklog.erb`):

```erb
<%- # Worklog template with register controls -%>
<%- if episodes == :multi_entry -%>
<%= timestamp_1 %> - <%= participant_1 %> <%= verbal_process %> <%= recipient %> regarding <%= issue %>
<%= timestamp_2 %> - <%= participant_2 %> <%= material_process %> <%= system %>
<%- elsif episodes == :two_entry -%>
<%= timestamp_1 %> - <%= participant_1 %> <%= action_1 %>
<%= timestamp_2 %> - <%= participant_2 %> <%= action_2 %>
<%- else -%>
<%= timestamp_1 %> - <%= participant_1 %> <%= action %>
<%- end -%>
```

**Validation class**:

```ruby
# lib/sfl/core/pass1/scenario_validator.rb
module SFL
  module Core
    module Pass1
      class ScenarioValidator
        def initialize(knobs)
          @knobs = knobs
          @sidecar = Sidecar.new
        end

        def validate_worklog(text)
          # Check verbal process density
          verbal_count = count_verbal_process_verbs(text)
          density = verbal_count.to_f / text.split.size * 100
          
          target_density = case @knobs[:process_mix]
                           when :material_only then 0..10
                           when :material_verbal then 30..60
                           when :verbal_dominant then 60..100
                           end
          
          target_density.cover?(density) || raise(ValidationError, 
            "Verbal process density #{density.round(1)}% outside target range #{target_density}")
          
          # Additional validations for participants, episodes, etc.
          validate_participants(text)
          validate_episodes(text)
          validate_span(text)
          
          text
        end

        private

        def count_verbal_process_verbs(text)
          # Call spaCy sidecar to count verbal process verbs
          @sidecar.count_pos_tags(text, pos: "VERB", lemma: VERBAL_PROCESS_LEMMAS)
        end
        
        VERBAL_PROCESS_LEMMAS = %w[post reply call ping leave inform message
                                   email contact notify update].freeze
      end
    end
  end
end
```

---

## 5. Where this runs in SFL Engine architecture

**Critical principle**: Generation happens **outside** the main pipeline,
similar to the DSPy variant's separation:

```
ERB Templates + Knob Sampler (Ruby, offline)
        │
        ▼
[Reviewed YAML fixtures] → lib/sfl/core/fixtures/scenarios.yaml
        │
        ▼
Pass 1 Sidecar (spaCy, seeded) → lib/sfl/core/pass1/extractor.rb
        │
        ▼
Pass 2 Annotation (ruby_llm, seeded) → lib/sfl/llm/pass_two_annotator.rb
```

**Why this matters for SFL Engine**:

1. **Reproducibility**: `scenarios.yaml` is versioned. The sidecar uses
   `random.choices()` with a fixed seed (20260809) to sample scenarios.

2. **Separation of concerns**: Template generation (Ruby) ≠ clause extraction
   (spaCy) ≠ semantic annotation (ruby_llm). Each pass has a single responsibility.

3. **Testability**: The knob sampler can be unit tested independently of spaCy.
   The validator can be tested with mock spaCy responses.

**File locations**:

```
lib/sfl/core/pass1/
├── scenario_generator.rb    # Knob sampling, ERB rendering
├── scenario_validator.rb    # spaCy-based validation
├── templates/
│   ├── symptom.erb
│   ├── worklog.erb          # All six knobs applied here
│   └── resolution.erb
└── fixtures/
    └── scenarios.yaml        # Reviewed, committed output
```

---

## 6. Effective-N in SFL Engine context

Current synthetic incident corpus: 70 records (35 real, 35 synthetic from seed 20260809).

**Knob grid**: 3 × 4 × 3 × 3 × 3 × 3 = **972 register combinations** per CI pool.

**SFL Engine's advantage**: The existing corpus already has **9 CI pools**
(Synapse, EPIC, PowerScribe, RadAssist, Fluency, etc.). With knob-based generation:

- **Without knobs**: Adding more records means more of the same (material-heavy)
- **With knobs**: Adding records means **sampling from underrepresented register cells**

**Implementation strategy**:

```ruby
# lib/sfl/core/pass1/scenario_sampler.rb
module SFL
  module Core
    module Pass1
      class ScenarioSampler
        def initialize(ci_pool, existing_coverage)
          @ci_pool = ci_pool
          @existing_coverage = existing_coverage
        end

        def underweighted_cells
          # Return cells where current coverage < target distribution
          # For verbal_dominant: target 23%, current likely ~0%
          # For multi_day: target 14%, current likely 0%
          
          TARGET_DISTRIBUTIONS.each_with_object([]) do |(knob, distribution), cells|
            distribution.each do |value, target_pct|
              current_pct = @existing_coverage[@ci_pool][knob][value] || 0
              cells << {knob: knob, value: value} if current_pct < target_pct * 0.8
            end
          end
        end

        def generate_for_cell(knob, value)
          # Sample other knobs coherently, render template, validate
          full_knobs = coherent_sample(knob, value)
          text = render_template(:worklog, full_knobs)
          ScenarioValidator.new(full_knobs).validate_worklog(text)
          full_knobs.merge(generated_text: text)
        end
      end
    end
  end
end
```

---

## 7. Integration with existing SFL Engine components

### Pass 1 Sidecar (`lib/sfl/core/pass1/sidecar.rb`)

The existing sidecar already supports text input → clause output. No changes
needed to core extraction logic. **Add validation endpoint**:

```ruby
# New method in Sidecar class
def validate_scenario(text, knob_constraints)
  # Run spaCy pipeline, return validation results
  # Check: verbal process density, participant count, etc.
  {valid: true, violations: [], metrics: {verbal_density: 0.45, ...}}
end
```

### Pass 2 Annotator (`lib/sfl/llm/pass_two_annotator.rb`)

No changes required. Pass 2 receives clause extraction output from Pass 1,
regardless of whether the input was real or knob-generated synthetic.

### Pipeline (`lib/sfl/pipeline.rb`)

Update the `ingest` method to accept a `source:` parameter:

```ruby
# In SFL::Pipeline#ingest
def ingest(text, source: :real, metadata: {})
  case source
  when :real
    # Existing real data path
  when :synthetic
    metadata[:register] ||= {} # Expect knob values here
    # Store metadata for provenance tracking
  end
  
  # Continue to Pass 1 extraction
  pass1_result = @pass1_extractor.extract(text)
  pass2_result = @pass2_annotator.annotate(pass1_result)
  
  # Store with full provenance
  store(pass2_result, source: source, metadata: metadata)
end
```

---

## 8. What this does NOT fix (SFL Engine edition)

**Scope limitations** (same as DSPy variant):
- Site-wide incident scope → needs `scope` field in scenario content
- Parent-incident relationships → needs scenario type, not knob
- Priority coherence → separate bug in sampling logic

**SFL Engine-specific limitations**:
- **Field bleed**: Pass 1's entity extraction cannot recover scrubbed PII.
  This is a data preprocessing issue, not a generation issue.
- **Scrub-map gaps**: Real data scrubbing inconsistencies. Knobs don't affect
  this because they control synthetic generation, not real data processing.

**New risk for SFL Engine**:

The register knobs make synthetic data **more realistic** from an SFL perspective.
However, SFL Engine's **stance-filtering effectiveness** depends on accurate
clause-level separation of ideational vs interpersonal content.

**Risk**: If synthetic data is *too* realistic (verbal process density matches
real), but still lacks the **subtle stance markers** that distinguish human
communication, Pass 2 annotation may overfit to synthetic patterns.

**Mitigation**: 
1. Maintain separate evaluation sets (real-only for stance-filter validation)
2. Track stance extraction accuracy on real vs synthetic data separately
3. Add stance-specific validation to `ScenarioValidator`

---

## 9. Suggested implementation order (Ruby/SFL Engine)

1. **Create `ScenarioGenerator` and `ScenarioValidator` classes**
   - Start with worklog templates only (highest ROI)
   - Implement `underweighted_cells` sampling
   - Add basic spaCy validation

2. **Generate 10 scenarios into underweighted cells**
   - Focus: `verbal_dominant`, `escalated`/`multi_team`, `two_entry`/`multi_entry`
   - Review and commit to `scenarios.yaml`

3. **Re-run SFL-proxy measurements**
   - Use existing measurement code from `docs/use-cases/sfl-dspy-scenario-authoring.md`
   - Target: SYN verbal process 6% → 60%+

4. **Integrate with `SFL::Pipeline`**
   - Add `source: :synthetic` parameter
   - Store knob metadata for provenance

5. **Add stance-specific validation**
   - Extend `ScenarioValidator` to check for stance markers
   - Ensure synthetic data doesn't degrade Pass 2 accuracy

---

## 10. Testing strategy

```ruby
# spec/lib/sfl/core/pass1/scenario_generator_spec.rb
RSpec.describe SFL::Core::Pass1::ScenarioGenerator do
  describe "#generate" do
    it "produces worklogs with target verbal process density" do
      generator = described_class.new(process_mix: :verbal_dominant)
      worklog = generator.generate(:worklog, ci_pool: "Synapse")
      
      validator = SFL::Core::Pass1::ScenarioValidator.new(
        process_mix: :verbal_dominant
      )
      
      expect { validator.validate_worklog(worklog) }.not_to raise_error
    end

    it "rejects incoherent knob combinations" do
      expect {
        described_class.new(
          participants: :solo,
          process_mix: :verbal_dominant
        ).generate(:worklog, ci_pool: "Synapse")
      }.to raise_error(SFL::Core::Pass1::IncoherentKnobsError)
    end
  end
end

# spec/lib/sfl/core/pass1/scenario_sampler_spec.rb
RSpec.describe SFL::Core::Pass1::ScenarioSampler do
  describe "#underweighted_cells" do
    it "identifies cells below target coverage" do
      coverage = {
        "Synapse" => {
          process_mix: {material_only: 0.8, material_verbal: 0.18, verbal_dominant: 0.02}
        }
      }
      sampler = described_class.new("Synapse", coverage)
      
      cells = sampler.underweighted_cells
      expect(cells.map { |c| c[:value] }).to include(:verbal_dominant)
    end
  end
end
```

---

*Sources: Adapted from `docs/use-cases/sfl-dspy-scenario-authoring.md`;
measurements from `synthetic_incidents.json` (70 records, seed 20260809);
SFL Engine architecture from `lib/sfl.rb`, `lib/sfl/core/pass1/sidecar.rb`,
`lib/sfl/llm/pass_two_annotator.rb`; SFL metafunction mapping from
`docs/architectural-lineage.md`.*
