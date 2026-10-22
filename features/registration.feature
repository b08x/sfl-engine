# Registration scenarios (design question 3). Kept in a SEPARATE file
# tagged @registration because registration in SFL::Ingest::
# DeterministicRules + Core::Loaders::Catalog is gated on a later user
# approval: until it is approved, the two loaders exist and are tested in
# isolation (see transcription_source.feature and
# image_meta_source.feature) but no ingest path reaches them.
#
# Tension resolved here: a broad ".txt => transcription" rule would capture
# every non-transcription text file in the vault. The rule below is
# basename-narrow (transcription_*.txt, matching every real source file in
# ~/Notebook/Daily) so ordinary .txt notes fall through to the classifier,
# exactly as today. The same narrowing applies to YAML: only
# image-*.meta.yaml matches, not .yaml or .meta.yaml in general.
@registration
Feature: Transcription and image-meta files classify deterministically into their new loaders

  Background:
    Given the production loaders SFL::Core::Loaders::TranscriptionSource and SFL::Core::Loaders::ImageMetaSource exist and are tested

  Scenario: A transcription-named .txt file classifies deterministically
    When SFL::Ingest::DeterministicRules.classify is called with a path whose basename matches "transcription_*.txt"
    Then it returns format "transcription", mode "conversation" and source_type "transcription"
    And the ingest path resolves that source_type to a TranscriptionSource factory that takes a ref and an optional file_id
    And a real file from ~/Notebook/Daily named transcription_<date>_<time>.txt matches the rule

  Scenario: An ordinary .txt file still falls through to the classifier
    When SFL::Ingest::DeterministicRules.classify is called with a path named "notes.txt", "todo.txt" or "README.txt"
    Then it returns nil, meaning the classifier decides, and the file is never sent to TranscriptionSource
    And this is the documented resolution of the broad-.txt capture tension

  Scenario: An image meta sidecar classifies deterministically
    When SFL::Ingest::DeterministicRules.classify is called with a path whose basename matches "image-*.meta.yaml"
    Then it returns format "image_meta", mode "knowledge_base" and source_type "vault_image_meta"
    And the ingest path resolves that source_type to an ImageMetaSource factory that takes a ref and an optional file_id

  Scenario: Other YAML files still fall through to the classifier
    When SFL::Ingest::DeterministicRules.classify is called with a path named "config.yaml", "note.meta.yaml" or "docker-compose.yml"
    Then it returns nil, so no existing YAML consumer changes behavior

  Scenario: Both loaders are registered in the loader catalog
    When Core::Loaders::Catalog registers its leaf loaders into the registry
    Then the registry resolves :transcription to a TranscriptionSource factory
    And the registry resolves :image_meta to an ImageMetaSource factory
    And both are simple ref-plus-optional-kwarg factories, registered alongside :subtitle and :markdown

  Scenario: A file whose content does not match its classified name is contained by the loader, not by the rule
    Given a file named "image-not-really.meta.yaml" whose content is not an image-meta mapping
    When it is classified and dispatched to ImageMetaSource
    Then the loader raises SFL::Core::Loaders::Error for the malformed shape
    And the ingest boundary rescues it and queues or skips the file rather than dispatching it elsewhere
    And the file's raw content is never executed or instantiated, only parsed

  Scenario: Ingest of a real transcription file end to end
    Given the registration rules above are live and a real transcription file from ~/Notebook/Daily
    When the ingest CLI walks that file
    Then it is classified without calling the LLM classifier
    And its turns are stored as sections under one document, with section ids "#{file_id}#turn-N"
    And the run reports the file as ingested, not queued for review
