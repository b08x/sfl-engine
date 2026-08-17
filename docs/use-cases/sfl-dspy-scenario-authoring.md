# SFL register knobs for scenario authoring — a DSPy design

**Scope as chosen:** register knobs only (no clause annotation layer), Python DSPy,
offline scenario authoring. Measurements below are from
`synthetic_incidents.json` (70 records, seed 20260809); the target values are the
real half's own numbers, not invented ones.

---

## 1. The gap, measured

The v2 memo said synthetic worklogs are "clean and short." That was true but not
actionable. Scoring both halves on SFL-proxy signals gives something you can tune
against — percentage of records carrying at least one marker, and mean density
per 100 words:

| Signal | % REAL recs | % SYN recs | mean/100w REAL | mean/100w SYN |
|---|---:|---:|---:|---:|
| **Verbal process** (posted, replied, called, pinged, left VM, informed) | **77%** | **6%** | 1.86 | 0.15 |
| **Waiting / suspension** (awaiting, on hold, no response, callback) | **69%** | **6%** | 0.95 | 0.15 |
| Material process (remoted, cleared, restarted, reinstalled) | 63% | **86%** | 1.59 | **4.11** |
| **Modality / hedging** (might, should, probably, not sure, pending) | **31%** | **6%** | 0.38 | 0.15 |
| Informal / typo (ill, dont, gonna, yea, *teram*, *lauching*) | 11% | 0% | 0.12 | 0.00 |
| Mental process (think, noticed, seems, figured) | 9% | 6% | 0.11 | 0.14 |

And on textual organisation:

| Signal | REAL | SYN |
|---|---:|---:|
| Worklogs with **≥2 timestamped entries** | 18/35 (51%) | **0/35** |
| Worklogs spanning **≥2 dates** | 5/35 (14%) | **0/35** |
| Distinct named parties (median) | 8 | 2 |
| Characters (median / max) | 599 / 1428 | 204 / **268** |

**The headline is one sentence: synthetic worklogs are made almost entirely of
material processes, and real ones are made of talk.** 77% of real worklogs
contain someone posting, calling, pinging, or leaving a voicemail; 6% of
synthetic ones do. Radiology IT support at L1 is a *verbal* activity — the
analyst's day is mostly relaying, escalating, and waiting — and the generator
models it as a lone technician performing operations on machines.

Two honest caveats, because the temptation is to claim all three process types
diverge:

- **Mental processes show no meaningful gap** (9% vs 6%). Neither half does much
  interior reasoning in writing. Don't build a knob for it.
- **Informal/typo is a weak signal** (11% vs 0%). Real, but at n=4 records it
  can't carry a target. Treat as a flavour parameter, not a metric.

---

## 2. Why this maps cleanly onto SFL, and why that's more than vocabulary

The three metafunctions each name a distinct failure, and each one has a
different fix — which is the practical reason to use the framing rather than
just saying "make it messier."

| Metafunction | Register variable | What's missing | Knob |
|---|---|---|---|
| **Ideational** | Field | Process-type mix is inverted — material-only, no verbal | `process_mix` |
| **Interpersonal** | Tenor | One participant, no power gradient, no hedging | `participants`, `modality` |
| **Textual** | Mode | Single-shot monologue; no episodic structure | `episodes`, `span` |

The value of keeping them separate is that they fail independently. A worklog can
be long and multi-party (Tenor fixed) and still be a single uninterrupted block
(Mode broken). Lumping them into one "realism" slider is what produces text that
is uniformly *more* of everything and still wrong.

---

## 3. The knobs

Six parameters, all `Literal`-typed so DSPy validates them at call time and the
caller cannot drift outside the set.

```python
from typing import Literal

ProcessMix   = Literal["material_only", "material_verbal", "verbal_dominant"]
Participants = Literal["solo", "pair", "escalated", "multi_team"]
Modality     = Literal["categorical", "hedged", "uncertain"]
Episodes     = Literal["single", "two_entry", "multi_entry"]
Span         = Literal["same_hour", "same_day", "multi_day"]
Register     = Literal["clean", "hurried", "fragmented"]
```

**Sampling weights, set from the real half** — this is the point of measuring
first. These are targets, not aesthetics:

| Knob | Distribution | Derived from |
|---|---|---|
| `process_mix` | material_only 23%, material_verbal 54%, verbal_dominant 23% | 77% of real carry ≥1 verbal |
| `participants` | solo 23%, pair 30%, escalated 30%, multi_team 17% | median 8 distinct named parties |
| `modality` | categorical 69%, hedged 23%, uncertain 8% | 31% of real hedge |
| `episodes` | single 49%, two_entry 31%, multi_entry 20% | 18/35 have ≥2 entries |
| `span` | same_hour 40%, same_day 46%, multi_day 14% | 5/35 span ≥2 dates |
| `register` | clean 66%, hurried 23%, fragmented 11% | 11% carry typo markers |

A seventh knob is tempting and should be resisted: **do not add a "realism"
master dial.** It would let a caller satisfy the aggregate while leaving the
verbal deficit untouched.

---

## 4. The chain

Three steps, because the coherence requirement in `synthetic-data-from-corpus`
SKILL.md ("symptom, worklog, and resolution are one unit") means the worklog must
be authored *from* the symptom, and the resolution *from* the worklog — not
sampled beside them. That was regression R1 in the v2 profile and it is the one
thing not to reintroduce.

```
       ci + register knobs
                │
         ┌──────▼───────┐
         │   Symptom    │   short_description, description
         └──────┬───────┘
                │ symptom
         ┌──────▼───────┐
         │   Worklog    │   ← all six knobs apply here
         └──────┬───────┘
                │ worklog
         ┌──────▼───────┐
         │  Resolution  │   resolution_notes + resolution_code
         └──────┬───────┘   (must name an action present in worklog)
                │
          scenarios.yaml (reviewed, committed)
```

```python
import dspy
from typing import Literal

class DraftSymptom(dspy.Signature):
    """Write a radiology IT ticket symptom as the reporting user would phrase it —
    imprecise, sometimes wrong about the cause, never using internal jargon."""
    configuration_item: str = dspy.InputField(desc="Synapse, EPIC, PowerScribe, RadAssist, Fluency, ...")
    register: Register       = dspy.InputField()
    short_description: str   = dspy.OutputField(desc="one line, the user's own words")
    description: str         = dspy.OutputField(desc="1-2 sentences, adds detail the title omits")

class DraftWorklog(dspy.Signature):
    """Write the analyst work notes for this ticket. Match the requested register
    exactly: process_mix governs whether steps are actions on systems (material) or
    communication with people (verbal); participants governs how many distinct people
    appear; episodes governs how many timestamped entries; span governs elapsed time."""
    short_description: str   = dspy.InputField()
    description: str         = dspy.InputField()
    process_mix: ProcessMix    = dspy.InputField()
    participants: Participants = dspy.InputField()
    modality: Modality         = dspy.InputField()
    episodes: Episodes         = dspy.InputField()
    span: Span                 = dspy.InputField()
    register: Register         = dspy.InputField()
    work_notes: str          = dspy.OutputField(desc="timestamped entries, newest first, '- > ' bullet style")

class DraftResolution(dspy.Signature):
    """Summarise how the ticket was resolved. Every action named here MUST appear in
    the work notes. Do not introduce a fix the worklog does not contain."""
    short_description: str = dspy.InputField()
    work_notes: str        = dspy.InputField()
    resolution_notes: str  = dspy.OutputField(desc="1-2 sentences")
    resolution_code: Literal[
        "Solved (Permanently)", "Solved (Work Around)", "Solved (First Call Resolution)"
    ] = dspy.OutputField()

class ScenarioAuthor(dspy.Module):
    def __init__(self):
        super().__init__()
        self.symptom    = dspy.Predict(DraftSymptom)
        self.worklog    = dspy.ChainOfThought(DraftWorklog)
        self.resolution = dspy.Predict(DraftResolution)

    def forward(self, configuration_item, **knobs):
        s = self.symptom(configuration_item=configuration_item, register=knobs["register"])
        w = self.worklog(short_description=s.short_description,
                         description=s.description, **knobs)
        r = self.resolution(short_description=s.short_description,
                            work_notes=w.work_notes)
        return dspy.Prediction(
            short_description=s.short_description, description=s.description,
            work_notes=w.work_notes, resolution_notes=r.resolution_notes,
            resolution_code=r.resolution_code,
        )
```

`ChainOfThought` on the worklog step only — it is the one step where the model
has to reconcile six constraints, and it is where reasoning earns its cost.
`Predict` elsewhere.

---

## 5. Where this runs — and where it must not

`synthetic-data-from-corpus/SKILL.md` already settled this, and the rule is
right:

> LM generation is legitimate for synthesizing records because no corpus text is
> involved. […] Require generated scenarios to be reviewed and committed as a
> versioned fixture (`scenarios.yaml`) so the pipeline itself stays
> seed-deterministic.

So:

```
DSPy (offline, non-deterministic, reviewed)  →  scenarios.yaml  →  pipeline.py (seeded)
```

**DSPy never enters `pipeline.py`.** It is a scenario-authoring tool run
deliberately, whose output a human reads before it is committed. `pipeline.py`
keeps sampling from `scenarios.yaml` with `random.choices()` under seed 20260809
and stays reproducible. This is not a limitation to work around later — it is
what makes the dataset citable.

Practical consequence: the knobs are sampled **at authoring time**, once per
scenario, and the chosen values get written into `scenarios.yaml` alongside the
text. That makes the fixture self-documenting — you can see at review time that
you have 12 `verbal_dominant` scenarios and 4 `multi_day` ones, instead of
inferring it from the prose.

```yaml
Synapse:
- short_description: Synapse is frozen and won't respond
  description: ...
  work_notes: ...
  resolution_notes: ...
  resolution_code: Solved (First Call Resolution)
  register:                      # new block — authoring provenance
    process_mix: material_verbal
    participants: escalated
    modality: hedged
    episodes: two_entry
    span: same_day
    style: clean
```

`pipeline.py` ignores the `register` block; it exists for review and for
measuring coverage.

---

## 6. Effective-N is the actual win

The current fixture holds **9 CI pools** and 35 synthetic records draw from them
— the v2 profile's R2 finding (effective N ≈ 9–12), which v5 reported as fixed by
deepening the pools. Deepening pools by hand is linear work.

The knob grid is **3 × 4 × 3 × 3 × 3 × 3 = 972 register combinations per CI.**
Not all are sensible — `solo` + `multi_team` is incoherent, `single` episode +
`multi_day` span is contradictory — and the weights make most rare. But it turns
scenario authoring from "write 20 more worklogs" into "sample 20 register cells
you don't yet cover," which is the difference between more examples and more
*variety*.

Two guards worth building in:

1. **Reject incoherent cells before calling the LM** — a small validity table,
   not a model call. `span=multi_day` requires `episodes != single`;
   `participants=solo` forbids `process_mix=verbal_dominant`.
2. **Report register coverage, not just count**, when the fixture is committed —
   same discipline as reporting effective-N alongside `total_records`.

---

## 7. What this does not fix, and one risk it creates

**Does not fix:**

- **Scope.** No knob makes a ticket site-wide. Multi-user scope is a *fact about
  the incident*, not a register setting — it belongs in the scenario content or a
  separate `scope` field. Both multi-user records in the corpus are real
  (`INC0062744`, `INC0063814`); the synthetic half has zero, and register tuning
  will not change that.
- **Parent-incident structure.** `INC0062744`'s "copied from Parent Incident"
  shape is relational, not stylistic. Needs a scenario type, not a knob.
- **Priority coherence.** The 11 synthetic matrix violations are a sampling bug in
  `pipeline.py`, untouched by this.
- **Field bleed and the scrub-map gaps** (§7 of the demo-strategy memo). Separate
  defects.

**Risk it creates — worth deciding before you run it.** Every measurement above
is also a provenance classifier. Closing the verbal-process gap makes synthetic
records harder to distinguish from scrubbed-real ones, which is the stated goal
for evaluation purposes. But all 70 records now carry `INC` prefixes, and the
only remaining markers are the `synthetic` boolean and `contact_name_source`.
The better this works, **the more the dataset depends on metadata alone to tell a
fabricated ticket from a real person's scrubbed one** — and the more consequential
the DATA-PROVENANCE question already open from the demo-strategy memo becomes.

That is not an argument against doing it. It is an argument for deciding the
provenance question first, since this work makes it harder to answer later.

---

## 8. Suggested order

1. Build the validity table and the knob sampler (no LM) — cheap, and it tells
   you how many coherent cells exist per CI.
2. Author 10 scenarios into the *underweighted* cells only: `verbal_dominant`,
   `escalated`/`multi_team`, `two_entry`/`multi_entry`. That is where the entire
   measured gap lives.
3. Re-run the §1 measurements on the regenerated dataset. The targets are the
   REAL column. If `% SYN recs` for verbal process moves 6% → 60%+, it worked.
4. Only then consider the optimizer path — a DSPy metric scoring generated text
   against these same measurements would let `MIPROv2` tune the instructions
   automatically. You declined that scope, correctly: measure by hand first and
   confirm the knobs move the numbers before automating the loop.

---

*Sources: measurements computed from `synthetic_incidents.json` this session;
pipeline architecture from `~/Workspace/RISIT/hipaa_pipeline/synthetic-data-from-corpus/SKILL.md`
and `scenarios.yaml`; DSPy API verified against Context7 `/llmstxt/dspy_ai_llms_txt`
(class-based signatures, `Literal` field typing, `dspy.Module` subclassing with a
`forward` method). SFL framing follows the clause-level principles in your
`ruby-dev:genai` skill and the register/tenor pattern in
`SPACY-SFL-KNOWLEDGE-REPRESENTATION.md`; your Drive notes were not reachable this
session and have not been reconciled against this.*
