# The SFL Engine as an Instrument for Human-AI Dialogue: A Case Study

**Purpose of this document**: reference material for a possible chapter proposal to
*Pedagogy in the Age of Artificial Intelligence: Human-AI Symbiosis, Dialogical
Experiments, and the Future of Education* (Edward Elgar Publishing, eds. Michael A.
Peters & J. Owen Matson, chapter proposals due 15 November 2026). This is not the
proposal itself — it's an honest inventory of what the SFL Engine actually does,
written so a future 400-600 word abstract can be built on what's real rather than
what sounds good.

## What information is in scope

Three things, in order: (1) what Systemic Functional Linguistics contributes to a
question about human-AI dialogue that isn't already answered by sentiment analysis
or topic modeling; (2) what the SFL Engine concretely measures, with real output
shapes, not aspirational ones; (3) where the honest gap is between "a working
instrument" and "a pedagogical finding" — because right now this is the former, not
the latter, and any chapter pitch needs to be honest about that distinction.

## Why SFL, not sentiment analysis

Michael Halliday's Systemic Functional Linguistics treats every clause as doing
three things simultaneously — its three *metafunctions*:

- **Ideational**: what happened (the process type — material, mental, relational,
  verbal — and who/what filled which role: Actor, Goal, Recipient, Circumstance)
- **Interpersonal**: the relationship being enacted (mood, modality — how certain
  the speaker is — and tenor, roughly the formality/social distance of the
  exchange)
- **Textual**: how the message is organized as a coherent message

SFL is not a novelty pick for this CFP's themes — Halliday's own tradition already
has a decades-long applied lineage in literacy and genre pedagogy (register theory,
"Reading to Learn," genre-based writing instruction in Australian systemic
functional linguistics). The move this project makes is applying that same
apparatus to a text genre SFL wasn't originally built for: human-AI dialogue
transcripts. A question like "what does it mean to know something in symbiotic
relation with an AI" is partly an epistemic-stance question — and epistemic stance
(modality) is one of SFL's three metafunctions, not a metaphor bolted onto it.
Sentiment analysis tells you whether a chatbot reply "sounds positive." SFL tells
you whether it's hedging, asserting, or instructing — and whether that shifts over
the course of a session.

## What the system concretely does

The SFL Engine (Ruby, `~/WorkspaceV3/sfl-engine`, mid-rebuild of an earlier
version) is a two-pass annotation pipeline:

- **Pass 1** (`lib/sfl/core/pass_one/`): a Python spaCy sidecar produces a real
  dependency parse for each sentence — tokens, POS tags, and syntactic dependency
  relations (subject, object, prepositional complement, etc.), addressed
  positionally rather than by text lookup so repeated words don't collapse onto
  the same head. `IdeationalExtractor` then maps those dependency labels onto SFL
  participant roles (`nsubj` → Actor, `dobj` → Goal, `xcomp`/`ccomp` → Process,
  and so on) — this is the mechanical bridge from syntax to Halliday's Ideational
  metafunction.
- **Pass 2** (`lib/sfl/llm/`): an LLM annotator produces the Interpersonal payload
  per clause — mood, a 0.0-1.0 modality weight, a 0.0-1.0 tenor value, speaker
  attitude, and (optionally) a structured reasoning trace: the premises, the
  inference rule, and a confidence score the annotation was derived from, hashed
  for reproducibility (`Core::Types::ReasoningTrace`).
- **Conversation-level aggregation** (`Core::Types::SpeakerProfile`,
  `Core::Types::KeyMoment`): per-speaker rollups — turn count, average tenor,
  tenor range and variance, average modality, mood distribution, dominant process
  types — plus automatic detection of five kinds of *key moments* in a
  conversation: `tenor_shift`, `modality_shift`, `topic_shift`,
  `semantic_anomaly`, `deflation_anomaly`.
- **Human-in-the-loop review** (`lib/sfl/store/pg_annotation_review_repository.rb`):
  every LLM-produced annotation the system isn't confident about lands in a review
  queue; a human can accept it, reject it, or trigger a Pass-2-only re-annotation.
  The audit trail is permanent and separate from the clause's own current values —
  what a human decided is never silently overwritten by a later re-annotation.

Critically for this CFP's theme: **the input format is not neutral prose — it's
dialogue.** `lib/sfl/core/loaders/chatgpt_export_source.rb` and
`claude_export_source.rb` parse ChatGPT's and Claude.ai's own conversation export
formats directly (walking ChatGPT's branching mapping-tree export into a linear
turn sequence, reading Claude's `chat_messages` array) into the same per-turn
`Types::Unit` structure every other input source produces. This was not built as a
demo for this chapter — it already exists, because the system's original purpose
was analyzing the author's own AI-assisted work sessions. That means: this is not
a proposal to build an instrument for studying human-AI dialogue. The instrument
already exists and already ingests the two most widely used consumer AI dialogue
formats.

## What a `SpeakerProfile` + `KeyMoment` pass over an AI tutoring transcript would
## surface (concretely, not hypothetically)

Given a conversation export, the system currently produces, per speaker:

```
avg_tenor: 0.42          # this speaker's formality/social-distance average
tenor_variance: 0.08     # how much that shifts turn to turn
avg_modality: 0.71       # this speaker's average epistemic certainty
mood_distribution: { "declarative" => 34, "interrogative" => 6, "imperative" => 2 }
dominant_processes: { "material" => 12, "mental" => 18, "relational" => 9 }
```

and, across the conversation as a whole, a list of flagged moments — a
`modality_shift` where certainty dropped sharply (a hedge, a correction, an "I'm
not sure"), a `tenor_shift` where formality changed (a register break — often a
meaningful pedagogical event: the moment a tutor drops formality to reassure a
frustrated learner, or a student's tone shifts from performing competence to
actually asking for help).

None of this is sentiment. None of it is a topic label. It is a structural,
theory-grounded description of *how* something was said, turn by turn, on both
sides of a human-AI exchange — which is closer to what "dialogical experiment" and
"human-AI symbiosis" actually need as an empirical vocabulary than most NLP
tooling offers by default.

## The honest gap

This system has **not** been run on a corpus of pedagogical AI transcripts, has
**no** published findings, and has never been used in an actual teaching context.
It is infrastructure, verified working (full pipeline, real dependency parsing,
real LLM annotation, a Postgres-backed store, an HTTP API, 655 passing specs as of
this writing) — not a study. Any chapter pitch drawing on this has exactly two
honest framings available:

1. **Practice-based / methodological**: present the instrument itself — the SFL
   metafunction framework applied to human-AI dialogue, the concrete data shapes
   above, the case for why register/stance analysis is a more theoretically
   grounded lens than sentiment analysis for studying "dialogical" pedagogy — as a
   proposed methodology, explicit that no findings exist yet.
2. **Do the small study first**: run the pipeline against a real AI-tutoring or
   AI-assisted-learning transcript set (even a self-collected one — the author's
   own ChatGPT/Claude history is directly ingestible right now, no new code
   needed) before the 15 November 2026 deadline, and pitch actual findings instead
   of a proposed instrument.

Option 2 is stronger for an edited academic volume that explicitly asks for
"empirically informed, or practice-based" contributions — but it requires actually
running the analysis and looking honestly at what comes out, including if the
results are messy or don't support a clean narrative.

## Why the reader (future-self, drafting the abstract) should care

The CFP asks what it means "to educate, to know, and to become human in symbiotic
relation with artificial intelligence." SFL's whole premise is that meaning is
made simultaneously at three levels every time anyone — human or model — produces
an utterance. A pipeline that already measures those three levels, already reads
the two dominant AI chat export formats, and already tracks how stance and
certainty shift turn-by-turn across a human-AI exchange is not a stretch fit for
this call. It is a genuinely unusual contribution for this kind of philosophy-and-
policy-leaning volume: most contributors will bring theory or classroom
observation. This is a working instrument that could produce data those other
chapters don't have access to — but only if it's actually pointed at real
transcripts before the deadline, not just described.
