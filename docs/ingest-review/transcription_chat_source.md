# Candidate loader: TranscriptionChatSource

Drafted for: `/home/b08x/Notebook/Daily/transcription_2025-05-11_14-31-02.txt`
Confidence: 0.8

## Field mapping

The file content appears to be a transcription of a conversation. Each line is treated as a separate unit of text spoken by the user. The `speaker` is assumed to be 'User' for all lines, and the `sent_at` timestamp is set to the current time. This mapping is chosen because the content does not explicitly differentiate between speakers or timestamps, and no existing loader matches this format.

## Status

**Not registered.** Review `transcription_chat_source.rb`, then wire it in:
add a `require` and a matching entry in `SFL::Ingest::DeterministicRules` before this
loader runs against real data.
