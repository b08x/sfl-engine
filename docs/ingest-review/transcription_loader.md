# Candidate loader: TranscriptionLoader

Drafted for: `/home/b08x/Notebook/Daily/transcription_2025-04-25_19-45-27.txt`
Confidence: 0.8

## Field mapping

The file sample appears to be a transcription of a conversation or monologue. Each line of the file is treated as a separate unit of text. The speaker is assumed to be 'User' for simplicity, and the sent_at timestamp is set to the current time. No existing loader matched because the format is a plain text transcription without explicit speaker or timestamp information.

## Status

**Superseded — consolidated into `SFL::Core::Loaders::TranscriptionSource`** at
`lib/sfl/core/loaders/transcription_source.rb`. The draft file `transcription_loader.rb`
this doc accompanied was removed, together with the other two transcription drafts
(`transcription_chat_source.rb`, `transcription_text_loader.rb`), and replaced by that one
production loader. Resolved field mapping: one turn per non-blank line, `speaker "User"`
with `is_user: true`, `sent_at` from the file's mtime (load time when the ref has no mtime).

Registered: files whose basename matches `transcription_*.txt` route deterministically via
`SFL::Ingest::DeterministicRules` to source_type `transcription`, which the ingest orchestrator
resolves to the `:transcription` factory in `Core::Loaders::Catalog`. Ordinary `.txt` files are
unaffected — they still fall through to the classifier.

Behavior is proven by `spec/core/loaders/transcription_source_spec.rb`.
