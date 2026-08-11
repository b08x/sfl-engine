# Audio/Video Loaders + Corpus-Onboarding Wizard ("Inversion") — Design

## Overview

The current corpus mixes markdown, PDF, image, audio, and video. Markdown,
PDF, and image are already handled (`Core::Loaders::MarkdownSource`,
`PdfSource`, `ImageSource`), dispatched via `Ingest::DeterministicRules` and
`Analysis::KnowledgeBaseSource`. Audio and video have no loader and no
deterministic routing rule — today they would fall into
`Ingest::Orchestrator`'s classifier/loader-drafter fallback path, which
samples the first 4KB of a file as text; that's meaningless for binary media
and was never intended to cover it.

This design has two parts, built in order:

1. **`AudioSource` / `VideoSource`** — close the format gap, following the
   exact precedent `ImageSource` already set.
2. **Inversion: a corpus-onboarding wizard** — a per-run interview that scans
   a target path, shows what analyses (image/audio/video) would cost in LLM
   calls, and lets the user opt in/out before running `ingest`, instead of
   requiring them to already know and hand-pick `--images`/`--audio`/`--video`
   flags. This does not replace `Ingest::Orchestrator`'s per-file
   classification (how to parse one file) — it decides per-run policy (which
   expensive analyses are worth paying for on this corpus).

Both parts follow this codebase's existing conventions: Zeitwerk-mapped
files, constructor-injected collaborators (`Boot` is the sole ENV reader),
`Core::Loaders::Source` duck typing, and the `Boot::TASK_NAMES` per-task
LLM config registry.

## Part 1 — AudioSource / VideoSource

### Gem verification

- `RubyLLM.transcribe(file, ...)` — native Whisper-backed transcription,
  already a transitive capability of the `ruby_llm` gem already in the
  Gemfile. Supports `.mp3 .wav .m4a .ogg .flac`; 25MB file-size limit.
  Verified via Context7 (`/crmne/ruby_llm`).
- `RubyLLM.chat(model: "gemini-2.5-flash").ask(..., with: "clip.mp4")` —
  video-capable chat, `.mp4 .mov .avi .webm`. Verified via Context7: **video
  support is provider-limited to Gemini/VertexAI**, unlike image support
  which works broadly. This matters for task-config defaults below.
- `kreuzberg` was checked and confirmed **not** to support audio or video
  (verified against its own docs) — it stays scoped to the document formats
  it already covers (PDF, etc.); it is not a candidate for this part.

### AudioSource

`lib/sfl/core/loaders/audio_source.rb`, mirroring `ImageSource`'s shape:

```ruby
class AudioSource
  include Source

  SUPPORTED_EXTENSIONS = %w[.mp3 .wav .m4a .ogg .flac].freeze

  def initialize(path, transcriber:, file_id: nil)
    @path = path.to_s
    @transcriber = transcriber # #transcribe(path) -> String, wraps RubyLLM.transcribe
    @file_id = file_id || File.basename(@path, ".*")
  end

  def each_unit
    # transcribe -> one Types::Unit; on failure, fallback stub + "transcription_failed"
    # metadata flag, same graceful-degradation shape as ImageSource#describe_image
  end
end
```

`transcriber:` is injected rather than calling `RubyLLM.transcribe` directly,
matching `ImageSource` taking `chat:` rather than calling `RubyLLM.chat`
itself — keeps the loader testable with a plain double and keeps model/task
resolution in `Boot`/`ChatFactory`, not scattered into loader classes.
`RubyLLM.transcribe` is a module-level function (not a `ChatFactory`-built
chat object), so the injected collaborator is a small adapter object
responding to `#transcribe(path) -> String`, not a raw `RubyLLM::Chat`.

One `Types::Unit` per file for this iteration (transcription segments/
timestamps are available from `RubyLLM.transcribe`'s result but splitting a
transcript into multiple units by segment is future work, not required to
close the current gap).

### VideoSource

`lib/sfl/core/loaders/video_source.rb`, same shape as `ImageSource` exactly
(`chat:` injected, one `Types::Unit` per file, vision-style prompt, graceful
fallback on failure):

```ruby
SUPPORTED_EXTENSIONS = %w[.mp4 .mov .avi .webm].freeze
```

### New Boot task names

`Boot::TASK_NAMES` gets two new entries, per the existing "one concern, one
task name" convention (`ingest_classification` and `loader_drafting` are
already separate tasks for exactly this reason):

- `:audio_transcription` — default provider inherits from
  `:pass_two_annotation`'s resolved default, same reasoning `:context_synthesis`
  already uses (no legacy equivalent, borrow a provider already trusted for
  Pass 2 rather than invent a new default).
- `:video_analysis` — **default provider is `:gemini`**, not inherited,
  because video input is Gemini/VertexAI-only per the Context7 verification
  above. An override to a non-video-capable provider via
  `SFL_TASK_VIDEO_ANALYSIS_PROVIDER` will fail at the `chat.ask(..., with:
  video)` call, which is an acceptable, loud failure — no special guard
  needed beyond what `ImageSource`-style graceful degradation already
  provides.

### DeterministicRules

`classify_audio`/`classify_video` module functions mirroring
`classify_image`, both returning `mode: "knowledge_base"` (audio/video are
knowledge-base content, same as image, not conversation transcripts — those
already exist as `.srt/.vtt/.ass` via `NATIVE_CHAT_EXTENSIONS`, a distinct
and already-solved case). Wired into `DeterministicRules.classify` the same
way `ImageSource::SUPPORTED_EXTENSIONS` already is.

### KnowledgeBaseSource wiring

`AUDIO_EXTENSIONS`/`VIDEO_EXTENSIONS` constants (same
`Core::Loaders::*Source::SUPPORTED_EXTENSIONS` delegation `IMAGE_EXTENSIONS`
already uses), `analyze_audio:`/`analyze_video:` opt-in constructor flags
(default off, matching `analyze_images:`), each requiring their respective
collaborator (`transcriber:` / `chat:`) when enabled — mirrors the existing
`raise ArgumentError, "chat: is required when analyze_images: true"` guard.

### CLI wiring

`--audio`/`--no-audio` and `--video`/`--no-video` flags on the
`knowledge-base` and `ingest` subcommands, alongside the existing
`--images`/`--no-images`. `build_kb_source` gets two more conditional
`chat_factory.for(...)` / transcriber-adapter calls, gated on
`options[:audio]` / `options[:video]` exactly as `options[:images]` already
gates the vision chat.

### Error handling

Same graceful-degradation shape `ImageSource` already uses: a failed
transcription/video-analysis call logs a warning and falls back to a
filename/format stub unit with a truthful `"transcription_failed"` /
`"video_analysis_failed"` metadata flag, rather than raising — consistent
with `Orchestrator#process`'s existing F11 partial-failure-isolation
principle (one file's issue never halts the rest of the run). This is a
plain-exception codebase at this layer (`Orchestrator#process` uses a plain
`rescue ... => e`, not `Dry::Monads`), so the new loaders follow that
observed convention rather than introducing a different error-handling style
for just these two classes.

### Testing

RSpec, mirroring `spec/core/loaders/image_source_spec.rb` exactly: a fixture
file, a plain `double` for the injected collaborator (`transcriber`/`chat`),
one example asserting the unit's text/document_id, one asserting the
collaborator was called with the right path/attachment shape, and a
failure-path context asserting graceful fallback + the truthful failure
flag. No shared example exists yet for `Loaders::Source` conformance across
`MarkdownSource`/`PdfSource`/`ImageSource`/`AudioSource`/`VideoSource`; introducing
one is worth doing here since it would now cover five classes, not
duplicating per-class "is_a?(Source)" checks — noted as a small
in-scope addition, not deferred.

## Part 2 — Inversion: corpus-onboarding wizard

### Why this is still needed

`bin/setup-config` already covers *global*, one-time Constraints (LLM
provider/model per task). It does not cover *per-run* policy: every `ingest`
invocation still requires the user to already know about and hand-pick
`--images`/`--audio`/`--video`, with no visibility into what's actually in
the target corpus or how many LLM calls enabling each flag will trigger.
That gap is real and is what "Inversion" (Discovery → Constraints →
Synthesis) still meaningfully addresses — scoped now to *run policy*, not to
building a whole separate RAG pipeline (the earlier standalone-project spec
this supersedes).

### Discovery

`Onboarding::CorpusScanner` walks the target path (reusing
`Ingest::Orchestrator#files`'s directory-walk shape) and tallies files by
the same extension groups `DeterministicRules`/`KnowledgeBaseSource` already
use (text/markdown/pdf, image, audio, video, chat exports, unrecognized).
The wizard (`tty-prompt`, matching `bin/setup-config`'s existing UI) prints
that tally, then asks one free-text question: "what are you trying to get
out of this corpus?"

That free-text answer is parsed into structured intent via
`RubyLLM::Schema` (verified via Context7: `chat.with_schema(SomeSchema).ask(...)`
returns a parsed `Hash`, not a validated/persisted object) using a new
`Onboarding::CorpusIntentSchema` and the `:corpus_onboarding` task (another
new `Boot::TASK_NAMES` entry). The returned Hash is intent-only input to
Constraints below — `ruby_llm-schema` shapes this one LLM call's output
contract; it does not validate or persist the run's actual config.

### Constraints

Given the tally + extracted intent, the wizard asks, per modality present in
the corpus (skipping any modality with zero files):

- Enable `--images`/`--audio`/`--video`? Shown alongside the file count for
  that modality as a direct LLM-call-count estimate (one call per file for
  audio/video, per current one-unit-per-file design; images likewise) so the
  cost trade-off is visible rather than guessed.
- Reuse the global default provider/model (from `.env` /
  `bin/setup-config`), or override per-run for this corpus specifically
  (writes explicit `SFL_TASK_*` overrides for just this run, not persisted
  globally).

### Synthesis

`Onboarding::Profile` (`Dry::Struct`: target path, per-modality
enabled/disabled, any per-run provider overrides, the extracted intent Hash)
gets persisted to `.sfl-corpus-profiles/<slug>.yml` (slug derived from the
target path's basename). The wizard then prints the equivalent
`sfl-analyze ingest <path> [--images] [--audio] [--video] --store` invocation
and asks whether to run it now or just save the profile for later. Running
it now shells out to the existing `CLI.run_ingest` path unchanged — the
wizard never talks to `Ingest::Orchestrator` directly, keeping the
established CLI parsing/dispatch as the single entry point.

### New CLI subcommand

`sfl-analyze onboard <path>` — added to `CLI::USAGE` and
`CLI.parse`'s command whitelist alongside the existing five subcommands, its
own `parse_onboard_options` (just `--output-dir`/`--disable-tracing`, no
modality flags — those are the wizard's own interactive questions, not
argv flags, since the whole point is not requiring the user to already know
them).

### Error handling

Same plain-exception convention as the rest of `CLI`/`Ingest`: a scan
failure (unreadable directory) raises and is reported the same way
`run_ingest`'s existing top-level error handling already reports a bad
input path — no new error-handling style introduced for this subcommand.

### Testing

RSpec for `CorpusScanner` (fixture directory with a known mix of extensions,
assert the tally), `Onboarding::Profile` (Dry::Struct validation/coercion
round-trip through YAML), and the wizard itself using `tty-prompt`'s test
helpers (`TTY::Prompt::Test`), matching how an interactive-prompt-driven
tool in this ecosystem is conventionally tested — no existing wizard spec to
mirror here since `bin/setup-config` has no spec coverage today; this is a
new pattern for the codebase, kept small (one wizard, one spec file) rather
than building shared test infrastructure speculatively.

## Build order

1. `AudioSource` + `VideoSource` + their `DeterministicRules`/
   `KnowledgeBaseSource`/CLI wiring — unblocks the current corpus
   immediately and has no dependency on Part 2.
2. `Onboarding::CorpusScanner` + `CorpusIntentSchema` + `Wizard` + `Profile`
   + the `onboard` subcommand — depends on Part 1 existing so the wizard has
   real audio/video flags to offer.

## Out of scope

- Splitting audio transcripts into multiple units by segment/timestamp.
- A shared `Onboarding::Profile` UI for editing a saved profile after the
  fact (re-run `onboard` to overwrite, for now).
- Any changes to `Ingest::Orchestrator`'s per-file classification/drafting
  logic — Part 2 sits entirely in front of it, at the CLI-invocation level.
