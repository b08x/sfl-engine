# Candidate loader: TranscriptionLoader

Drafted for: `/home/b08x/Notebook/Daily/transcription_2025-04-25_19-45-27.txt`
Confidence: 0.8

## Field mapping

The file sample appears to be a transcription of a conversation or monologue. Each line of the file is treated as a separate unit of text. The speaker is assumed to be 'User' for simplicity, and the sent_at timestamp is set to the current time. No existing loader matched because the format is a plain text transcription without explicit speaker or timestamp information.

## Status

**Not registered.** Review `transcription_loader.rb`, then wire it in:
add a `require` and a matching entry in `SFL::Ingest::DeterministicRules` before this
loader runs against real data.
