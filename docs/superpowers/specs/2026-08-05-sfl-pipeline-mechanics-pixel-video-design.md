# SFL Engine — Pipeline Mechanics Pixel-Simulation Video Overview

## Context

The SFL Engine NotebookLM notebook (`3da35aa6-8b7e-433d-9092-dfd29e9678b4`) already has a `laboratory-notebook`-styled explainer video covering the Rhetorical Firewall / ideational-interpersonal separation story, using a lab/security metaphor set (evidence crates, glass firewall, warehouse of embeddings) defined in `docs/prompts/video/domains/sfl-engine.yaml` (in the `notebooklm-py` workspace).

This is a **second, complementary** video overview: same underlying `notebooklm-video` orchestration pipeline (style pack + domain pack + voice pack → Jinja2-compiled prompt → `client.artifacts.generate_video`), different visual language and narrower narrative scope.

## Resolved Tension: cinematic vs. explainer format

NotebookLM's `cinematic` video format renders through Veo 3 (photorealistic AI documentary footage) and ignores the `--style` parameter entirely — a hard API constraint, not a prompt-engineering gap. Pairing it with `pixel-simulation.yaml` (whose own constraints explicitly say "avoid photorealism") would not produce reliable pixel-art output; the existing `runner.py` workaround for cinematic/short formats only merges the style prompt into freeform instructions as a hint, with no enforcement.

**Decision: use the `explainer` format**, which supports `VideoStyle.CUSTOM` + `style_prompt` properly. This gets genuine, reliable pixel-art rendering — consistent with how the laboratory-notebook video was produced — at normal explainer render times (~3-8 min) with no special subscription requirement.

## Narrative Scope

Unlike the laboratory-notebook video (security/firewall framing), this video zooms into **pipeline mechanics**: how the two-pass annotation pipeline and hybrid RRF retrieval actually work as a system, told as a factory simulation. No firewall/security narrative — this is "how does the machine run," not "how is it defended."

Audience: broader/less specialist technical audience (not narrowed to RAG-security practitioners). Voice: `documentary` (broadcast-quality, hook → principles → live scenario → synthesis), which pairs naturally with pixel-simulation's factory/automation visual grammar.

## Components

### 1. New domain pack: `docs/prompts/video/domains/sfl-pipeline-mechanics.yaml`

A factory/automation-flavored concept mapping, distinct from the existing `sfl-engine.yaml` (lab/security flavor). Literal industrial metaphors instead of evidence-crate/firewall framing:

| SFL concept | Factory metaphor |
|---|---|
| Clause entering the pipeline | Raw material crate entering the factory floor |
| Pass 1 (spaCy) | Fast stamping machine — extracts structural parts (participants, processes) at line speed |
| Pass 2 (LLM) | Skilled inspector station — reads nuance, attaches quality tags (mood, modality, tenor) |
| Ideational payload output | Conveyor Belt A — the "fact parts" bin |
| Interpersonal payload output | Conveyor Belt B — the "stance tags" bin |
| Postgres/pgvector storage | Dual warehouse silos, one per belt, independently indexed |
| Incoming retrieval query | A dispatch order entering the yard |
| Vector similarity search | Automated forklift #1 — scans by proximity/similarity |
| Keyword/full-text search | Automated forklift #2 — scans by exact tag match |
| Reciprocal Rank Fusion | A merging conveyor junction where both forklifts' picks combine into one ranked cart via a visible scoring formula on a HUD |
| Scalar stance filter | Quality-control gate on the belt — rejects/dims flagged crates before the loading dock |
| LLM synthesis | The loading dock / delivery drone — only accepts QC-cleared crates |

`domain_rules` will emphasize: keep the two belts visually distinct end-to-end (color-coded), show the RRF junction as an explicit merge-with-formula moment (not implied), and treat the QC gate as a mechanical process shown in action, not narrated only.

### 2. Reused style pack: `docs/prompts/video/styles/pixel-simulation.yaml`

No changes — used as-is.

### 3. Reused voice pack: `docs/prompts/video/voices/documentary.yaml`

No changes — used as-is.

### 4. New project config: `examples/notebooklm-video/projects/sfl-engine-pipeline-mechanics.yaml`

```yaml
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

### 5. Execution

Reuses the existing `-n/--notebook-id` support added to `examples/notebooklm-video/runner.py` (targets the existing SFL Engine notebook, skips document re-upload) and the `task_id`-as-`artifact_id` download fix already applied.

```bash
uv run --with pyyaml --with pydantic --with jinja2 examples/notebooklm-video/runner.py \
  examples/notebooklm-video/projects/sfl-engine-pipeline-mechanics.yaml \
  -n 3da35aa6-8b7e-433d-9092-dfd29e9678b4 \
  --execute \
  --out .../sfl-engine-pipeline-mechanics.mp4
```

## Out of scope

- No changes to the existing `sfl-engine.yaml` domain pack or the laboratory-notebook video.
- No cinematic/Veo 3 generation.
- No new style pack — pixel-simulation is used unmodified.

## Testing / Verification

- Dry-run compile (`runner.py` without `--execute`) to inspect the rendered style prompt and instructions before submitting to Video Studio, same as done for the laboratory-notebook video.
- Live execution is a manual, confirmed step (video generation is long-running / rate-limit sensitive per the notebooklm skill's autonomy rules) — not run automatically as part of this spec's implementation.
