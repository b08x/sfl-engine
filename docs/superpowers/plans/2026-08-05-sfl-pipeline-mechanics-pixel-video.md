# SFL Pipeline Mechanics Pixel-Simulation Video — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a dry-run-verified `notebooklm-video` project (new domain pack + new project config) that compiles a pixel-simulation-styled, documentary-voiced explainer script for the SFL Engine notebook, focused on two-pass annotation + hybrid RRF retrieval mechanics — ready for a human-confirmed live execution afterward.

**Architecture:** Two new declarative YAML files consumed by the existing `notebooklm-video` compiler (`examples/notebooklm-video/compiler/`): a domain pack (concept mappings) and a project config (ties together style/domain/voice packs + custom instructions). No Python code changes — `runner.py` already supports `-n/--notebook-id` targeting and the `task_id`-as-artifact-ID download fix from prior work. Verification is a dry-run compile (`runner.py` without `--execute`), which loads and Pydantic-validates both YAML files and renders the Jinja2 templates with zero network calls.

**Tech Stack:** YAML, Pydantic v2 (via the existing `compiler/models.py` schemas), Jinja2 (existing templates), `uv run` for ad-hoc dependency execution.

## Global Constraints

- Domain pack file: `docs/prompts/video/domains/sfl-pipeline-mechanics.yaml` (repo: `/home/b08x/WorkspaceV3/notebooklm-py`), validated against `compiler.models.DomainPack` (fields: `name`, `description`, `concept_mapping: dict[str,str]`, `domain_rules: list[str]`, `tags: list[str]`).
- Project config file: `examples/notebooklm-video/projects/sfl-engine-pipeline-mechanics.yaml` (same repo), validated against `compiler.models.ProjectConfig`.
- Reuse `docs/prompts/video/styles/pixel-simulation.yaml` and `docs/prompts/video/voices/documentary.yaml` unmodified.
- Target notebook ID for later live execution: `3da35aa6-8b7e-433d-9092-dfd29e9678b4` (SFL Engine) — not invoked in this plan, only documented for the handoff.
- No live `--execute` run, no network calls, no artifact generation in this plan — that is a separate, explicitly confirmed step outside this plan's scope (per the notebooklm skill's autonomy rules: `generate *` is long-running/rate-limit-sensitive and requires confirmation).
- Concept mapping content, `domain_rules`, and `custom_instructions` text must match what's specified in `docs/superpowers/specs/2026-08-05-sfl-pipeline-mechanics-pixel-video-design.md` (sfl-engine repo) — copied verbatim below, not paraphrased.

---

### Task 1: Create the `sfl-pipeline-mechanics` domain pack

**Files:**
- Create: `/home/b08x/WorkspaceV3/notebooklm-py/docs/prompts/video/domains/sfl-pipeline-mechanics.yaml`

**Interfaces:**
- Consumes: nothing (leaf YAML file)
- Produces: a `DomainPack`-shaped YAML document loadable by `compiler.loaders.load_domain_pack("sfl-pipeline-mechanics")`, which resolves to `docs/prompts/video/domains/sfl-pipeline-mechanics.yaml` under the default `NOTEBOOKLM_PROMPT_LIBRARY` root. Task 2 consumes this by referencing `domain: "sfl-pipeline-mechanics"` in its project config.

- [ ] **Step 1: Write the domain pack YAML**

Create `/home/b08x/WorkspaceV3/notebooklm-py/docs/prompts/video/domains/sfl-pipeline-mechanics.yaml` with exactly this content:

```yaml
name: sfl-pipeline-mechanics
description: Concepts and metaphors for the SFL Engine two-pass annotation pipeline and hybrid RRF retrieval, told as factory automation mechanics rather than security/firewall framing.
concept_mapping:
  clause entering the pipeline: raw material crate entering the factory floor
  Pass 1 (spaCy): fast stamping machine — extracts structural parts (participants, processes) at line speed
  Pass 2 (LLM): skilled inspector station — reads nuance, attaches quality tags (mood, modality, tenor)
  ideational payload output: Conveyor Belt A — the "fact parts" bin
  interpersonal payload output: Conveyor Belt B — the "stance tags" bin
  Postgres/pgvector storage: dual warehouse silos, one per belt, independently indexed
  incoming retrieval query: a dispatch order entering the yard
  vector similarity search: "automated forklift #1 — scans by proximity/similarity"
  keyword/full-text search: "automated forklift #2 — scans by exact tag match"
  Reciprocal Rank Fusion: a merging conveyor junction where both forklifts' picks combine into one ranked cart via a visible scoring formula on a HUD
  scalar stance filter: quality-control gate on the belt — rejects/dims flagged crates before the loading dock
  LLM synthesis: the loading dock / delivery drone — only accepts QC-cleared crates
domain_rules:
  - Keep the two conveyor belts (ideational "fact parts" vs interpersonal "stance tags") visually and chromatically distinct from the split point all the way to their separate warehouse silos
  - Show the Reciprocal Rank Fusion merge junction as an explicit mechanical moment with a visible scoring formula, not an implied or narrated-only event
  - Show the quality-control gate as a mechanical process acting on crates in real time, not just described in narration
  - This is a mechanics/how-it-works narrative, not a security narrative — do not introduce firewall, attack, or adversarial framing (that belongs to the separate laboratory-notebook video)
tags:
  - retrieval augmented generation
  - hybrid search
  - reciprocal rank fusion
  - nlp pipeline
  - systemic functional linguistics
  - pgvector
  - automation
  - simulation
```

- [ ] **Step 2: Validate the YAML parses and matches the DomainPack schema**

Run:
```bash
cd /home/b08x/WorkspaceV3/notebooklm-py
uv run --with pyyaml --with pydantic python3 -c "
import sys
sys.path.insert(0, 'examples/notebooklm-video')
sys.path.insert(0, 'src')
from compiler.loaders import load_domain_pack
pack = load_domain_pack('sfl-pipeline-mechanics')
print('name:', pack.name)
print('concept count:', len(pack.concept_mapping))
print('rules count:', len(pack.domain_rules))
assert pack.name == 'sfl-pipeline-mechanics'
assert len(pack.concept_mapping) == 12
assert len(pack.domain_rules) == 4
print('OK')
"
```
Expected output ends with `OK` (no traceback, no Pydantic `ValidationError`).

- [ ] **Step 3: Commit**

```bash
cd /home/b08x/WorkspaceV3/notebooklm-py
git add docs/prompts/video/domains/sfl-pipeline-mechanics.yaml
git commit -m "feat(video-prompts): add sfl-pipeline-mechanics domain pack

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Create the `sfl-engine-pipeline-mechanics` project config

**Files:**
- Create: `/home/b08x/WorkspaceV3/notebooklm-py/examples/notebooklm-video/projects/sfl-engine-pipeline-mechanics.yaml`

**Interfaces:**
- Consumes: `style: "pixel-simulation"` (existing `docs/prompts/video/styles/pixel-simulation.yaml`, unmodified), `domain: "sfl-pipeline-mechanics"` (Task 1's output), `voice: "documentary"` (existing `docs/prompts/video/voices/documentary.yaml`, unmodified)
- Produces: a `ProjectConfig`-shaped YAML document loadable by `compiler.loaders.load_project_config(...)`, consumed by `runner.py`'s `compile_from_yaml()` in Task 3's verification step and later by a human-confirmed `--execute` run (out of scope for this plan).

- [ ] **Step 1: Write the project config YAML**

Create `/home/b08x/WorkspaceV3/notebooklm-py/examples/notebooklm-video/projects/sfl-engine-pipeline-mechanics.yaml` with exactly this content:

```yaml
# Complementary video overview for the SFL Engine notebook (existing notebook,
# targeted via -n/--notebook-id — no new sources are uploaded). Companion to
# sfl-engine-rhetorical-firewall.yaml (laboratory-notebook style, security framing);
# this one is pixel-simulation style, pipeline-mechanics framing, no security narrative.

title: "SFL Engine: Inside the Pipeline"
style: "pixel-simulation"
domain: "sfl-pipeline-mechanics"
voice: "documentary"
audience: "General technical audience curious how RAG retrieval pipelines work"
length: "6-8 min"
video_format: "explainer"
documents: []
custom_instructions: >
  Open on a single crate rolling onto the factory floor. Send it through the fast
  stamping machine (Pass 1) which punches out structural tags, then the skilled
  inspector station (Pass 2) which reads nuance and clips on quality tags for mood,
  modality, and tenor. Show the crate physically splitting onto two color-coded
  conveyor belts — Belt A carrying "fact parts" into one warehouse silo, Belt B
  carrying "stance tags" into a separate silo. Cut to a dispatch order arriving in
  the yard: two automated forklifts launch in parallel, one scanning by proximity/
  similarity, one scanning by exact tag match, both converging at a merge junction
  where a visible scoreboard computes the combined ranking. The merged cart rolls
  through a quality-control gate that rejects or dims flagged crates before the
  loading dock, where only cleared crates are picked up for delivery. Keep the two
  belts visually and chromatically distinct end-to-end; make the RRF merge junction
  and QC gate explicit mechanical beats, not just narrated asides.
```

- [ ] **Step 2: Validate the YAML parses and matches the ProjectConfig schema**

Run:
```bash
cd /home/b08x/WorkspaceV3/notebooklm-py
uv run --with pyyaml --with pydantic python3 -c "
import sys
sys.path.insert(0, 'examples/notebooklm-video')
sys.path.insert(0, 'src')
from compiler.loaders import load_project_config
cfg = load_project_config('examples/notebooklm-video/projects/sfl-engine-pipeline-mechanics.yaml')
print('title:', cfg.title)
print('style:', cfg.style)
print('domain:', cfg.domain)
print('voice:', cfg.voice)
assert cfg.style == 'pixel-simulation'
assert cfg.domain == 'sfl-pipeline-mechanics'
assert cfg.voice == 'documentary'
assert cfg.video_format == 'explainer'
print('OK')
"
```
Expected output ends with `OK` (no traceback, no `ValidationError`).

- [ ] **Step 3: Commit**

```bash
cd /home/b08x/WorkspaceV3/notebooklm-py
git add examples/notebooklm-video/projects/sfl-engine-pipeline-mechanics.yaml
git commit -m "feat(video-prompts): add sfl-engine-pipeline-mechanics project config

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Full dry-run compile verification

**Files:**
- None created or modified — this task only runs the existing `runner.py` in dry-run mode (no `--execute`) against the files from Tasks 1 and 2.

**Interfaces:**
- Consumes: `examples/notebooklm-video/projects/sfl-engine-pipeline-mechanics.yaml` (Task 2), which transitively consumes `docs/prompts/video/domains/sfl-pipeline-mechanics.yaml` (Task 1), `docs/prompts/video/styles/pixel-simulation.yaml`, and `docs/prompts/video/voices/documentary.yaml` (both pre-existing, unmodified).
- Produces: a printed `CompiledPrompt` preview (style prompt + instructions) for human review before any live `--execute` run. Nothing is persisted by this task.

- [ ] **Step 1: Run the dry-run compiler**

```bash
cd /home/b08x/WorkspaceV3/notebooklm-py
uv run --with pyyaml --with pydantic --with jinja2 examples/notebooklm-video/runner.py \
  examples/notebooklm-video/projects/sfl-engine-pipeline-mechanics.yaml
```

- [ ] **Step 2: Verify the compiled output**

Check the printed output for all of the following:
- Header line reads: `✔ Synchronously compiled project: [SFL Engine: Inside the Pipeline]`
- `Style Pack:  pixel-simulation`
- `Domain Pack: sfl-pipeline-mechanics`
- `Voice Pack:  documentary`
- `Target:      explainer (6-8 min for General technical audience curious how RAG retrieval pipelines work)`
- The `[STYLE PROMPT ...]` section contains a `Domain Concept Mappings` block listing all 12 `concept_mapping` entries from Task 1 (e.g. `[Reciprocal Rank Fusion] ➔ visualize as: a merging conveyor junction...`)
- The `[STYLE PROMPT ...]` section's `Domain Pedagogical Rules` block lists all 4 `domain_rules` from Task 1, including the "not a security narrative" rule
- The `[CONTENT INSTRUCTIONS ...]` section's `Additional Project Custom Instructions` exactly matches the `custom_instructions` text from Task 2, Step 1
- No Python traceback, no `FileNotFoundError`, no `ValidationError`
- Final lines confirm dry-run mode: `[Note] Dry-run preview complete. No network calls or notebook creations occurred.`

If any check fails, fix the offending YAML file (Task 1 or Task 2) and re-run Step 1 before proceeding.

- [ ] **Step 3: No commit needed**

This task makes no file changes — it is a verification gate only. Proceed directly to the handoff note below.

---

## Handoff (out of scope for this plan)

Once Task 3 passes, live execution is a separate, explicitly human-confirmed step (long-running generation, subject to Google's rate limits):

```bash
cd /home/b08x/WorkspaceV3/notebooklm-py
uv run --with pyyaml --with pydantic --with jinja2 examples/notebooklm-video/runner.py \
  examples/notebooklm-video/projects/sfl-engine-pipeline-mechanics.yaml \
  -n 3da35aa6-8b7e-433d-9092-dfd29e9678b4 \
  --execute \
  --out /home/b08x/WorkspaceV3/sfl-engine/audio-overviews/sfl-engine-pipeline-mechanics.mp4
```

This targets the existing SFL Engine notebook (reusing the `-n/--notebook-id` support and the `task_id`-as-artifact-ID download fix already present in `runner.py` from prior work) and does not re-upload any sources.
