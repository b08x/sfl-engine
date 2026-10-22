# Design question 6: the four docs/ingest-review/*.md pairs that
# accompanied the drafts in 4a53727 must stop telling the reader the
# loaders are unregistered candidates. These scenarios pin what "updated"
# means, from the reader's perspective: no stale "Not registered" claim,
# the final class names, and an explicit supersession trail for the
# three drafts the consolidated loader replaces.
Feature: Ingest-review docs reflect the loaders' production state

  Background:
    Given the four ingest-review docs committed in 4a53727
      | doc                              | draft it accompanied       |
      | transcription_chat_source.md      | transcription_chat_source.rb |
      | transcription_loader.md          | transcription_loader.rb      |
      | transcription_text_loader.md     | transcription_text_loader.rb |
      | yaml_document_analysis_loader.md | yaml_document_analysis_loader.rb |

  Scenario: No doc still claims its loader is unregistered
    When a reader opens any of the four docs
    Then the Status section no longer contains "Not registered"
    And it no longer instructs the reader to add a require and a DeterministicRules entry

  @consolidation
  Scenario: The three transcription docs point at the one loader that superseded them
    When a reader opens any of the three transcription docs
    Then its Status section names SFL::Core::Loaders::TranscriptionSource at lib/sfl/core/loaders/transcription_source.rb as the superseding production loader
    And it says the draft file it accompanied was removed
    And it records the resolved mapping: one turn per non-blank line, speaker "User" with is_user true, sent_at from the file's mtime

  Scenario: The YAML doc points at the loader that superseded it
    When a reader opens the yaml_document_analysis_loader.md doc
    Then its Status section names SFL::Core::Loaders::ImageMetaSource at lib/sfl/core/loaders/image_meta_source.rb as the superseding production loader
    And it records the corrected mapping: one unit per file, text from "description", sent_at from "timestamp", attribution in metadata instead of a fabricated speaker

  @registration
  Scenario: Registered docs state the classification rule
    When registration is approved and lands
    Then each Status section states the deterministic rule that routes its files: basename "transcription_*.txt" for transcriptions and "image-*.meta.yaml" for image sidecars
    And each doc names the spec file that proves its loader's behavior
