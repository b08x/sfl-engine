# Candidate loader: TranscriptionTextLoader

Drafted for: `/home/b08x/Notebook/Daily/transcription_2025-05-04_17-19-58.txt`
Confidence: 0.8

## Field mapping

The provided file sample appears to be a transcription of a conversation. Each line of the file represents a segment of the conversation. Since there is no explicit speaker information or timestamp in the sample, the loader assumes 'Unknown' as the speaker and does not set a timestamp. The text field is directly mapped to each line of the file. No existing loader matched because the format is simple and does not include structured metadata like speaker or timestamp.

## Status

**Not registered.** Review `transcription_text_loader.rb`, then wire it in:
add a `require` and a matching entry in `SFL::Ingest::DeterministicRules` before this
loader runs against real data.
