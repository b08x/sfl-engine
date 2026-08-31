# Media Ingest + Corpus Onboarding — Design

**Date:** 2026-08-31
**Status:** Approved for planning
**Supersedes:** `2026-08-11-audio-video-loaders-and-corpus-onboarding-design.md` (entirely)
**Companion:** `2026-08-29-vault-annotation-substrate-design.md` (pairing, rules annotation, correlation, dataset export)

---

## What this merge resolves

Two designs were written against the same ground four days apart, and they
disagreed. This document replaces both of their audio/video/onboarding halves
with one coherent design.

The Aug 11 spec (`AudioSource`/`VideoSource` + "Inversion" wizard) was never
implemented — no `lib/sfl/llm/transcribers/`, no `lib/sfl/onboarding/`, no
`bin/setup-whisper`, and `whispercpp` is absent from the Gemfile. It is
superseded rather than amended.

| Question | Aug 11 said | Now | Why |
|---|---|---|---|
| Default transcriber | `RubyLlmTranscriber` (API + key) | **`WhisperCppTranscriber`** (local) | The substrate is local-by-default; no default path may require a key. Aug 11 predates that decision. |
| `#transcribe` returns | `String` (whole file) | **`Array<Segment>`** | whisper.cpp is *natively* segment-based — `context.transcribe(path, params) { |text| … }` yields per segment. Returning one string means **joining** what the backend already separated. Segments are the cheaper output, not the more expensive one. |
| Units per audio file | one | **one per segment** | Provenance should cite a moment in a recording, not a filename. The correlation half's evidence pane shows *where* a claim came from. |
| Transcriber namespace | `Llm::Transcribers::*` | **`Core::Ports::Transcriber`** | whisper.cpp is not an LLM. The `Llm::` namespace was correct only while the default backend was an API. Ports is where every other injected collaborator lives. |
| Video analysis | Gemini vision, one Unit/file | **audio-track extraction + local transcription**, vision opt-in | A vision model is LLM-only and Gemini-locked. The audio track of a screen recording or talk carries the actual claims, and extracting it is deterministic. |
| Wizard intent parsing | `RubyLLM::Schema` + `:corpus_onboarding` task | **dropped** | The wizard's value is the tally and the per-modality choice, both deterministic. Free-text intent extraction was the one part needing a provider. |
| Path → loader dispatch | extend `DeterministicRules` | **extend `DeterministicRules`** (unchanged) | Correct in Aug 11. The substrate spec's separate `Ingest::SourceResolver` duplicated it and is **dropped**. |

**Carried forward from Aug 11 unchanged**, because it was right and the
substrate spec simply missed it: `DeterministicRules` wiring,
`KnowledgeBaseSource` extension constants and opt-in flags, CLI flag wiring,
the `Boot::TASK_NAMES` treatment for opt-in LLM paths, plain-exception error
handling at this layer, and a shared example for `Loaders::Source`
conformance.

---

## Verified gem facts

Carried from Aug 11's Context7 verification, still current:

- **`whispercpp`** (`bindings/ruby` in ggml-org/whisper.cpp) — native binding.
  `Whisper::Context.new("base")` accepts a model name, a local `.bin` path, or
  a URI (auto-download + cache); `Whisper::Params.new(language:, …)`;
  `context.transcribe(path, params) { |text| … }`. Fully local, no network, no
  per-call cost. Mirrors Pass 1's spaCy-sidecar precedent (track decision 2).
- **`RubyLLM.transcribe(file, …)`** — Whisper-backed API transcription.
  `.mp3 .wav .m4a .ogg .flac`, 25 MB limit.
- **`RubyLLM.chat(...).ask(..., with: "clip.mp4")`** — video is
  **provider-limited to Gemini/VertexAI**, unlike image support.
- **`kreuzberg`** does **not** support audio or video. Confirmed against its
  own docs; it stays scoped to document formats.

**Cost to name, not gloss:** `whispercpp` is a native C extension compiled at
`bundle install`. Every install pays that cost regardless of which backend a
run uses. Accepted — this codebase already carries a heavier local dependency
for Pass 1 — but it is a real tax, and it is now on the *default* path rather
than an optional one.

---

## Part 1 — Transcription

### `Core::Ports::Transcriber`

```ruby
# @param path [String]
# @return [Array<Types::TranscriptSegment>]
# @raise [Transcriber::Error]
def transcribe(path)
```

With `Fake` (canned segments) and `Null` (always raises) implementations
alongside, matching the existing `Core::Ports::{fake,null}` layout.

### `Types::TranscriptSegment`

A `Dry::Struct` — `text` (String), `start_at` (Float), `end_at` (Float).
A named type rather than a bare Hash because it crosses a port boundary and
`AudioSource` reads its fields positionally; a typo in a Hash key would
surface as a `nil` in a Unit rather than as an error at the seam.

### `Llm::Transcribers::WhisperCppTranscriber` → `Core::Transcribers::WhisperCpp`

Wraps `Whisper::Context#transcribe`, collecting the yielded segments. Config
is a local model name or `.bin` path (`"base"`, `"base.en"`, `"small"`), **not**
a provider/model pair — so it does **not** go through `Boot::TASK_NAMES` /
`TaskConfig`. It is recorded per-run in the onboarding profile.

`bin/setup-whisper` (mirroring `bin/setup-python`'s spaCy vendoring) pre-warms
the model cache rather than paying an auto-download mid-run.

### `Core::Transcribers::RubyLlm` *(opt-in)*

Wraps `RubyLLM.transcribe`, resolved via a `:audio_transcription`
`Boot::TASK_NAMES` entry, default provider inherited from
`:pass_two_annotation` (the `:context_synthesis` precedent). Retained because
the substrate's policy is *local by default, LLM opt-in* — not *no LLM ever* —
and an API transcriber is the right escape hatch when whisper.cpp's local
quality is insufficient for a curated subset destined for a training set.

It has one segment-shaped wrinkle: `RubyLLM.transcribe` returns a string, not
segments. This adapter therefore emits **one segment spanning the whole file**
(`start_at: 0.0`, `end_at: nil`-equivalent) rather than faking timings it does
not have. `AudioSource` handles a single-segment transcript identically to a
many-segment one, so nothing downstream branches on backend.

### `Core::Loaders::AudioSource`

```ruby
SUPPORTED_EXTENSIONS = %w[.mp3 .wav .m4a .ogg .flac].freeze

def initialize(path, transcriber:, file_id: nil)
```

One `Types::Unit` per segment, `document_id` of `"<file_id>#audio-<index>"`,
with `start_at`/`end_at` in metadata.

**Failure emits a flagged Unit, never a drop and never a raise** — a
filename/format stub with `"transcription_failed" => true`, matching
`ImageSource#describe_image`'s precedent and `Orchestrator#process`'s F11
partial-failure isolation. Plain `rescue`, not `Dry::Monads`: this layer is a
plain-exception layer, and introducing a second error style for one class
would be worse than matching the observed convention.

## Part 2 — Video

`Core::Loaders::VideoSource`, `SUPPORTED_EXTENSIONS = %w[.mp4 .mov .avi .webm]`
(33 `.mp4` files in the target vault).

**Default path is local and deterministic:** extract the audio track with
`ffmpeg` to a temp file, hand it to the same injected `Transcriber`, emit one
Unit per segment exactly as `AudioSource` does. For a screen recording, a
talk, or a meeting, the audio track carries the claims; a vision model
describing the *pixels* would not.

**Opt-in vision analysis** (`--video-vision`) adds a `chat:`-injected
description Unit per file, via a `:video_analysis` `Boot::TASK_NAMES` entry
defaulting to `:gemini` (video input is Gemini/VertexAI-only). An override to
a non-video-capable provider fails loudly at `chat.ask(..., with: video)`,
which is acceptable — the graceful-degradation path already covers it.

**New dependency:** `ffmpeg` as a system binary, probed at construction with a
clear error naming the missing binary rather than a cryptic failure mid-run.
Not a gem, and not compiled at install time.

**Open question:** whether `VideoSource` should subclass or compose
`AudioSource`. Composition is the likely answer — `VideoSource` extracts, then
*delegates* to an `AudioSource` over the extracted track — but confirm against
the actual `Source` duck before committing to it.

## Part 3 — Dispatch and wiring

**This replaces the substrate spec's `Ingest::SourceResolver` entirely.** That
unit duplicated dispatch the codebase already performs.

- **`Ingest::DeterministicRules`** — add `classify_audio` / `classify_video`
  mirroring `classify_image`, both returning `mode: "knowledge_base"` (audio
  and video are knowledge-base content; conversation transcripts are the
  distinct, already-solved `.srt/.vtt/.ass` case under `NATIVE_CHAT_EXTENSIONS`).
  Wired into `.classify` the same way `ImageSource::SUPPORTED_EXTENSIONS` is.
- **`Analysis::KnowledgeBaseSource`** — `AUDIO_EXTENSIONS` / `VIDEO_EXTENSIONS`
  delegating to the loaders' own constants (as `IMAGE_EXTENSIONS` does), plus
  `analyze_audio:` / `analyze_video:` opt-in constructor flags defaulting to
  off, each raising `ArgumentError` when enabled without its collaborator —
  mirroring the existing `"chat: is required when analyze_images: true"` guard.
- **CLI** — `--audio`/`--no-audio`, `--video`/`--no-video` on the
  `knowledge-base` and `ingest` subcommands, plus
  `--transcriber whisper_cpp|ruby_llm` (**default `whisper_cpp`**) gating which
  adapter `build_kb_source` constructs.

## Part 4 — Onboarding wizard

Retained from Aug 11 with its one LLM dependency removed.

**The gap is real and unchanged:** every `ingest` invocation requires the user
to already know about and hand-pick `--images`/`--audio`/`--video`, with no
visibility into what is actually in the corpus.

- **`Onboarding::CorpusScanner`** walks the target path and tallies files by
  the same extension groups `DeterministicRules` uses. **It calls
  `DeterministicRules.classify`** rather than re-implementing extension
  sniffing — that duplication is exactly what the dropped `SourceResolver`
  would have introduced.
- **The wizard** (`tty-prompt`, matching `bin/setup-config`) prints the tally
  and asks per present modality whether to enable it. **Free-text intent
  extraction via `RubyLLM::Schema` is dropped** — it was the only part
  requiring a provider, and the tally plus explicit per-modality questions
  deliver the actual value.
- **The cost shown changes meaning.** Aug 11 framed it as LLM call count.
  Local transcription has no per-call cost, so the wizard shows **estimated
  wall-clock time** (file count × observed per-minute-of-audio rate), and
  shows call counts only for the opt-in LLM paths. If whisper.cpp's model is
  not yet cached, it offers to run `bin/setup-whisper` there rather than
  deferring that failure to mid-run.
- **`Onboarding::Profile`** (`Dry::Struct`) persists to
  `.sfl-corpus-profiles/<slug>.yml`: target path, per-modality flags,
  transcriber backend and model, any per-run provider overrides.
- **`sfl-analyze onboard <path>`** — new subcommand in `CLI::USAGE` and
  `CLI.parse`'s whitelist. It prints the equivalent `ingest` invocation and
  offers to run it, shelling out to the existing `CLI.run_ingest` path
  unchanged; the wizard never talks to `Ingest::Orchestrator` directly.

---

## Error handling

Plain exceptions at this layer, matching `Orchestrator#process`'s existing
`rescue … => e` rather than introducing `Dry::Monads` for these classes alone.

- Transcription or video-analysis failure → warning + stub Unit with a
  truthful `"transcription_failed"` / `"video_analysis_failed"` flag. One
  file's failure never halts a run (F11).
- Missing `ffmpeg` → `ArgumentError` at `VideoSource` construction naming the
  binary, not a cryptic failure at extraction time.
- Uncached whisper model → the wizard offers `bin/setup-whisper`; a direct CLI
  run auto-downloads via the gem's own caching.
- Unreadable scan directory → raises, reported as `run_ingest` already reports
  a bad input path.

## Testing

Mirroring `spec/core/loaders/image_source_spec.rb` exactly: a fixture file, a
fake for the injected collaborator, examples asserting unit text and
`document_id`, an example asserting the collaborator received the right path,
and a failure context asserting the stub plus the truthful flag.

- **`AudioSource`** is tested once against `Ports::Fake::Transcriber`; it does
  not know which adapter is behind it. Segment count, per-segment
  `document_id`, and `start_at`/`end_at` propagation are the load-bearing
  assertions.
- **Each adapter** gets a narrow spec asserting it satisfies
  `#transcribe(path) -> Array<TranscriptSegment>`. `WhisperCpp`'s spec stubs
  `Whisper::Context` rather than running a real native transcription; `RubyLlm`'s
  stubs the API call and asserts the single-whole-file-segment shape.
- **`VideoSource`** stubs `ffmpeg` extraction and asserts delegation to the
  transcriber, plus the missing-binary error.
- **A shared example for `Loaders::Source` conformance** — introduced here
  because it now covers six classes (`Markdown`, `Pdf`, `Canvas`, `Image`,
  `Audio`, `Video`) rather than duplicating per-class `is_a?(Source)` checks.
  `spec/support/shared_examples/ports.rb` is the existing precedent.
- **`CorpusScanner`** against a fixture directory with a known extension mix.
- **The wizard** via `TTY::Prompt::Test`. A new pattern for this codebase
  (`bin/setup-config` has no spec today), kept to one wizard and one spec file
  rather than building shared test infrastructure speculatively.

## Build order

1. `Types::TranscriptSegment` + `Ports::Transcriber` + fake/null.
2. `Core::Transcribers::WhisperCpp` + `bin/setup-whisper` + the Gemfile entry.
3. `Core::Loaders::AudioSource` + the `Loaders::Source` shared example.
4. `DeterministicRules` / `KnowledgeBaseSource` / CLI wiring for audio.
   **Audio is fully usable at this point**, before video or the wizard exist.
5. `Core::Loaders::VideoSource` + ffmpeg extraction + its wiring.
6. `Core::Transcribers::RubyLlm` + the `:audio_transcription` task entry (opt-in).
7. Opt-in video vision + the `:video_analysis` task entry.
8. `Onboarding::CorpusScanner` + `Profile` + wizard + `onboard` subcommand.

Steps 6–7 are the only ones touching an LLM, and both are opt-in; the corpus
is fully ingestible after step 5 with no API key.

## Out of scope

- Speaker diarisation. Segments carry timings, not identities.
- Re-transcribing on model change. A profile records which model produced a
  transcript; deciding when to invalidate is future work.
- Editing a saved profile in place — re-run `onboard` to overwrite.
- Any change to `Ingest::Orchestrator`'s per-file classification or drafting.
  Part 4 sits in front of it at the CLI-invocation level.
