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
```
