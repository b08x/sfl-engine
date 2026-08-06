# Claude Design Prompt — Web Frontend

**Purpose of this document**: a self-contained prompt to paste into claude.ai/design
to kick off UI work for a browser frontend over the SFL Engine's HTTP API
(`lib/sfl/api/`). Grounded in `docs/project-overview.md` — update that file first
if the API surface changes, then regenerate this prompt from it.

---

```
Design a web frontend for the SFL Engine — an internal, single-user developer
tool for browsing and reviewing SFL-annotated (Systemic Functional Linguistics)
text clauses stored via a Ruby HTTP API. This is not a multi-tenant product —
no auth/account screens needed, just the operator's own working console.

If my "Syncopated Notes Design System" project exists, reuse its visual
language (typography, spacing, dark mode). Otherwise, default to a dense,
developer-tool aesthetic: dark background, monospace for data/IDs, generous
use of tables, minimal chrome. Think "internal ops dashboard," not
consumer product.

## Screens needed

### 1. Corpus Browser
Paginated, filterable table of every stored clause.
- Filters: document_id, annotation_source, source_type, mood, process_type,
  min/max modality_weight (0-1 float), min/max tenor (0-1 float)
- Table columns: clause text (truncated), document_id, mood, process_type,
  modality_weight, tenor, annotation_source
- Click a row to open a Clause Detail panel/drawer showing the full
  breakdown: syntactic tokens (text/lemma/pos/dep), ideational payload
  (process_type, participants as role+text pairs, circumstances), and
  interpersonal payload (mood, modality_weight, tenor, speaker_attitude,
  reasoning, annotation_source, and — if present — a reasoning_trace with
  premises/inference_rule/conclusion/confidence).
- Backed by: GET /clauses (query params above + limit/offset) -> {clauses:[],
  total:, limit:, offset:}

### 2. Annotation Review Queue
A queue of clauses whose Pass-2 (LLM) annotation confidence needs human
sign-off — distinct from the Corpus Browser (this is a *workflow* queue,
not a browse view).
- List view: clause text, document_id, mood, process_type, current
  annotation_source, reasoning (why it's flagged)
- Per-item actions: Accept (sign off as-is), Reject (disagree, no
  replacement), Re-annotate (re-run the LLM annotation pass and show a
  before/after diff of the interpersonal fields — mood/tenor/modality
  changing is the key visual)
- Backed by: GET /clauses/review-queue (paginated) and
  POST /clauses/:id/review {decision: "accepted"|"rejected"|"re_annotated"}

### 3. Content Review Queue
A separate, earlier-stage queue: raw extracted/generated text (e.g. a
vision model's image description, a low-quality transcript) that needs
review *before* it's compiled into clauses at all.
- List view: modality (image/text/audio), source_file, reason flagged,
  generated_text preview
- Per-item actions: Approve, Reject, Edit (opens a text editor for the
  generated_text, submitting triggers a recompile — show a loading/
  progress state since this can take a few seconds)
- Backed by: GET /review-queue?modality= and
  POST /review-queue/:id/decide {decision: "approve"|"edit"|"reject",
  edited_text?}

### 4. Query Console
A single search box + results view for asking natural-language questions
against the corpus.
- Input: query text, optional filters (same scalar set as Corpus Browser
  minus document_id/annotation_source), limit
- Two response modes to design for:
  - Retrieve only: ranked list of matching clauses with rrf_score,
    semantic_rank, keyword_rank badges
  - Synthesize: an LLM-composed answer with inline citation markers
    linking back to the specific evidence clauses (cited_clause_ids),
    plus a confidence indicator and the raw evidence list below
- Backed by: POST /retrieve and POST /synthesize

### 5. Ad-hoc Compile
A simple form: paste raw text, optional document_id, checkboxes for
store/embed, submit -> shows the resulting annotated clauses (reuse the
Clause Detail component from screen 1).
- Backed by: POST /pipeline/compile

### 6. Document Upload Dashboard
Batch ingestion for the three source types `Analysis::Engine` already
compiles (conversation, documentation, knowledge-base) — the browser
equivalent of running `sfl-analyze` from the CLI, not a new pipeline.
- Drop zone accepting: native conversation files (.jsonl/.srt/.vtt/.ass),
  raw ChatGPT/Claude export .json files (multi-conversation — the backend
  expands one of these into many rows, see below), and
  documentation/knowledge-base files (.md/.pdf and directories).
- Per-source-type option toggles mirroring the CLI flags: --store,
  --narrative, --resume (conversation/documentation), --images/
  --vision-model (knowledge-base only).
- A raw export .json file must render as an *expansion* step before
  ingestion, not a single row: show "Expanding export... found N
  conversations" then list each resulting conversation as its own row
  (title, turn count) — a single multi-hundred-conversation upload is
  normal here, not an edge case.
- Batch status table, one row per file/conversation: filename/label,
  status (queued/processing/embedded/failed), clause count once done,
  and — critically — a per-row failure reason when status is "failed".
  One bad file must never blank out the rows around it; each file's
  outcome is independent and should render as soon as it's known, not
  only after the whole batch finishes.
- A persistent batch-level summary once complete: "847/900 succeeded,
  53 failed" with the failed rows filterable/expandable to their error
  messages — this is the UI expression of a real backend behavior
  (`SFL::CLI.run_conversation`'s per-file isolation: one conversation's
  compile failure no longer aborts the rest of the batch).
- Backed by: **no HTTP route exists for this yet** — `lib/sfl/api/server.rb`
  only exposes single-text `POST /pipeline/compile` today, not
  file/batch upload, background job status, or export expansion over
  HTTP (those currently only run via the `sfl-analyze` CLI, synchronously,
  in-process). Design the screen against the CLI's actual behavior
  (`SFL::CLI.run_conversation`/`run_documentation`/`run_knowledge_base`,
  `Analysis::ChatExportExpander`) as the source of truth for what each
  step does, but treat batch-status polling as a **new capability the
  backend would need first**: a job needs an id, a way to report
  per-file progress asynchronously (uploads of this size cannot compile
  synchronously inside one HTTP request), and a status endpoint to poll.
  Design the frontend against a plausible contract (e.g.
  `POST /uploads` -> `{job_id}`, `GET /uploads/:job_id` -> per-file
  status array) but flag it as speculative, not implemented.

### 7. Settings
A single screen showing the operator's current configuration —
primarily **read-only status**, not a live editor, because of a real
architectural constraint: `SFL::Boot` is the sole ENV reader and reads
once at process start (composition-root pattern); nothing today lets a
running server hot-reload a changed provider/model/database URL. Design
around that constraint rather than implying settings apply immediately.
- **LLM configuration** (per-task, mirrors `bin/setup-config`'s wizard
  and `SFL::Boot::TASK_NAMES`): for each of pass_two_annotation,
  pass_two_batch_annotation, context_synthesis, and embedding — current
  provider, current model, and whether that provider's required API key
  is present (a masked/boolean "key set" indicator only — never render
  the key value itself, this is a local single-user tool but secrets
  still shouldn't render to a screen).
- **Docker services status**: Postgres and Redis health (mirrors
  `docker-compose.yml`'s healthchecks — container up/down, port, and
  the auto-start behavior from `SFL::DockerServices.ensure_running!`).
- **Database**: current `DATABASE_URL` target (host/port/db name only,
  credentials masked), connection status.
- **Tracing**: whether Langfuse/OpenTelemetry tracing is currently
  active for this process (`--disable-tracing` equivalent status).
- Each section explains *how* to actually change it today — "edit
  `.env` and restart" / "run `bin/setup-config`" — rather than exposing
  inline form fields that silently wouldn't take effect. If a "regenerate
  config" action is designed in, it should shell out to the same
  `bin/setup-config` wizard flow conceptually, not duplicate its provider/
  model catalog by hand.
- Backed by: **no HTTP route exists for this yet** either — this is
  entirely new surface. A minimal real contract would be a
  `GET /settings` returning the current (non-secret) resolved config —
  design against that, flagged as speculative like screen 6.

## Cross-cutting notes
- This is a debugging/ops tool as much as a browsing tool — surface raw
  IDs, timestamps, and scores rather than hiding them; the user is the
  same person who built the backend.
- Design for a fast keyboard-driven workflow on the two review queues
  (screens 2 and 3) specifically — these are repetitive human-in-the-loop
  decisions, so minimize clicks per item (keyboard shortcuts for
  accept/reject/approve would be valuable).
- No destructive action needs a confirmation modal except the queue
  "reject" actions, which permanently clear stored clauses for that
  document.
- Screens 1-5 are grounded in HTTP routes that exist today
  (`lib/sfl/api/server.rb`) — design those as if wiring up a real
  backend. Screens 6 and 7 (Document Upload Dashboard, Settings) are
  **not** backed by any existing route; design them against the CLI's
  real behavior as the source of truth for what each control does, but
  keep the visual language identical across all seven screens so the
  two speculative ones don't read as a different, more "finished"
  product than the five real ones.
```
