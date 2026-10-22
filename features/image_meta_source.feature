# Image-meta YAML loader — acceptance scenarios for turning the
# yaml_document_analysis_loader.rb candidate draft (committed in 4a53727)
# into a loadable, tested production loader.
#
# Source data: image-*.meta.yaml sidecar files under ~/Notebook/Daily/assets
# — one YAML mapping per file with fields description / model_used /
# evaluation / timestamp, produced by an image-analysis pass. One file is
# one document in the glossary sense; the loader emits a single section.
#
# Naming decision (design question 2): the class is ImageMetaSource in
# image_meta_source.rb, not YamlMetaSource — the sibling loaders are named
# after what the file IS (MarkdownSource, ImageSource, SubtitleSource), not
# after its serialization format, and a format-named class would claim every
# .yaml file in the vault while this loader only understands the image-meta
# schema. If the user vetoes, YamlMetaSource in yaml_meta_source.rb is the
# drop-in alternative; only the class/file-name steps below change.
Feature: Image-meta YAML loader turns one image sidecar file into one section

  Background:
    Given an image-meta YAML file whose basename starts with "image-" and ends with ".meta.yaml"
    And the file's content is a YAML mapping with a "description" string and optionally "model_used", "evaluation" and "timestamp"
    And a file ref for that path built with the same helper the loader specs use (spec/support/file_ref_helper.rb)
    And a loader constructed as SFL::Core::Loaders::ImageMetaSource.new(ref, file_id:)

  Scenario: The draft is replaced by a Zeitwerk-valid class
    When the production change lands
    Then the class SFL::Core::Loaders::ImageMetaSource exists at lib/sfl/core/loaders/image_meta_source.rb
    And the file name matches the constant name so Zeitwerk can resolve it
    And the draft file yaml_document_analysis_loader.rb no longer exists under lib/sfl/core/loaders/
    And the class includes SFL::Core::Loaders::Source, so it is a Loaders::Source

  Scenario: A well-formed file yields exactly one unit
    Given a meta file with description "A whiteboard diagram of the ingest pipeline", model_used "gpt-4o", evaluation "good" and timestamp "2025-11-02T14:03:00Z"
    When the loader yields its units
    Then exactly 1 unit is yielded, and it is a SFL::Core::Types::Unit
    And its text is the description string
    And its section_id is "#{file_id}#meta"
    And its document_key is the ref's path_hint
    And its source_path is the ref's path_hint
    And its sent_at is the parsed timestamp as a Time
    And its metadata includes "file_id", "model_used" => "gpt-4o" and "evaluation" => "good"
    And its speaker is nil, because a document-analysis sidecar is not a speech turn — attribution lives in metadata, not in a fabricated speaker
    And its is_user is nil and its parent_section_id is nil

  Scenario: Missing optional fields leave metadata sparse but the unit emitted
    Given a meta file with only description "Screenshot of a terminal" and timestamp "2025-11-02T14:03:00Z"
    When the loader yields its units
    Then exactly 1 unit is yielded
    And its metadata has no "model_used" or "evaluation" keys

  Scenario: A missing or unparseable timestamp degrades, it does not fail the file
    Given a meta file whose "timestamp" key is absent
    When the loader yields its units
    Then exactly 1 unit is yielded with text from the description and sent_at nil
    And the same holds when the timestamp value is not a parseable time, and a single warning names the file and the unparseable value
    And no unit's sent_at is ever a fabricated wall-clock value

  Scenario: A missing or blank description is fatal
    Given a meta file with no "description" key
    When the loader yields its units
    Then a SFL::Core::Loaders::Error is raised naming the file
    And the same error is raised when the description is present but blank, because text is the unit's one required payload
    And the ingest boundary rescues that error without aborting the surrounding ingest run

  Scenario: Malformed YAML is fatal
    Given a meta file whose content is not parseable YAML
    When the loader yields its units
    Then a SFL::Core::Loaders::Error is raised naming the file
    And the same error is raised when the parsed root is not a mapping (a bare string or a sequence)

  # STRIDE: Elevation of privilege — YAML deserialization must not instantiate objects
  Scenario: YAML with ruby object tags is rejected without instantiating anything
    Given a meta file whose content uses YAML tags such as "!ruby/object:" to name a class
    When the loader yields its units
    Then a SFL::Core::Loaders::Error is raised naming the file
    And the YAML is parsed with the safe parser only, so no ruby object named in the file is ever instantiated
    And the ingest boundary rescues that error without aborting the surrounding ingest run

  # STRIDE: Tampering — type confusion in the mapped fields
  Scenario: A description that is not a string is rejected, not stringified
    Given a meta file whose "description" value is a nested mapping or a sequence
    When the loader yields its units
    Then a SFL::Core::Loaders::Error is raised naming the file
    And no unit is emitted with fabricated text such as an inspected Hash
