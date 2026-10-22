# Candidate loader: TranscriptionTextLoader

Drafted for: `/home/b08x/Notebook/Daily/transcription_2025-05-04_17-19-58.txt`
Confidence: 0.8

## Field mapping

The provided file sample appears to be a transcription of a conversation. Each line of the file represents a segment of the conversation. Since there is no explicit speaker information or timestamp in the sample, the loader assumes 'Unknown' as the speaker and does not set a timestamp. The text field is directly mapped to each line of the file. No existing loader matched because the format is simple and does not include structured metadata like speaker or timestamps.

## Status

**Superseded — consolidated into `SFL::Core::Loaders::TranscriptionSource`** at
`lib/sfl/core/loaders/transcription_source.rb`. The draft file `transcription_text_loader.rb`
this doc accompanied was removed, together with the other two transcription drafts
(`transcription_chat_source.rb`, `transcription_loader.rb`), and replaced by that one
production loader, which resolves the drafts' speaker conflict ("Unknown" vs "User") and
timestamp conflict (none vs wall clock) as approved. Resolved field mapping: one turn per
non-blank line, `speaker "User"` with `is_user: true`, `sent_at` from the file's mtime
(load time when the ref has no mtime).

Registered: files whose basename matches `transcription_*.txt` route deterministically via
`SFL::Ingest::DeterministicRules` to source_type `transcription`, which the ingest orchestrator
resolves to the `:transcription` factory in `Core::Loaders::Catalog`. Ordinary `.txt` files are
unaffected — they still fall through to the classifier.

Behavior is proven by `spec/core/loaders/transcription_source_spec.rb`.
