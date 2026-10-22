# Transcription loader — acceptance scenarios for turning the three
# transcription candidate drafts (committed in 4a53727) into one
# loadable, tested production loader.
#
# Source data: transcription_*.txt files in ~/Notebook/Daily — plain-line
# transcriptions, one spoken line per physical line, no speaker labels and
# no timestamp markers anywhere in the content.
#
# Tags:
#   @consolidation — the scenario only holds under the "one consolidated
#     TranscriptionSource replaces all three drafts" recommendation
#     (design question 1). Drop the tagged scenarios if the user vetoes
#     consolidation and three separate classes are kept instead.
Feature: Transcription loader turns plain-line transcription files into turns

  A plain-line transcription file is a document in the glossary sense:
  the whole file. Each non-blank physical line is a section — one turn,
  spoken by the user who dictated it. The loader normalizes it into
  SFL::Core::Types::Units following the SubtitleSource convention
  (ctor (ref, file_id:), #each_unit, section_id "#{file_id}#turn-#{index}",
  document_key from ref.path_hint, fatal cases raise Core::Loaders::Error
  rescued at the ingest boundary).

  Background:
    Given a plain-text transcription file whose lines are spoken text with no speaker labels and no timestamp markers
    And a file ref for that path built with the same helper the loader specs use (spec/support/file_ref_helper.rb)
    And a loader constructed as SFL::Core::Loaders::TranscriptionSource.new(ref, file_id:)

  @consolidation
  Scenario: One production loader replaces all three candidate drafts
    Given the three candidate drafts under lib/sfl/core/loaders/
      | draft file                   | draft class             | hardcoded speaker | timestamp policy   |
      | transcription_chat_source.rb | TranscriptionChatSource | "User"            | Time.now per line |
      | transcription_loader.rb      | TranscriptionLoader     | "User"            | Time.now per line |
      | transcription_text_loader.rb | TranscriptionTextLoader | "Unknown"         | none              |
    When the production change lands
    Then exactly one transcription loader class exists: SFL::Core::Loaders::TranscriptionSource
    And it lives at lib/sfl/core/loaders/transcription_source.rb so the file name matches the constant name for Zeitwerk
    And the three draft files no longer exist under lib/sfl/core/loaders/
    And every remaining file under lib/sfl/core/loaders/ parses as Ruby with no embedded markdown fences

  Scenario: Each non-blank line becomes exactly one turn
    Given a transcription file with 4 non-blank lines
    When the loader yields its units
    Then exactly 4 units are yielded, each a SFL::Core::Types::Unit
    And each unit's text is the corresponding line, stripped of leading and trailing whitespace
    And no unit's text is empty

  Scenario: Blank lines are skipped without a turn and without a warning
    Given a transcription file that contains blank and whitespace-only lines between spoken lines
    When the loader yields its units
    Then no unit is emitted for any blank or whitespace-only line
    And the loader writes no warning to stderr for those lines
    And the remaining non-blank lines each produce one unit, in file order

  Scenario: Turn section ids are contiguous over emitted turns only
    Given a transcription file with 3 non-blank lines separated by blank lines
    When the loader yields its units
    Then the units' section ids are "#{file_id}#turn-0", "#{file_id}#turn-1" and "#{file_id}#turn-2"
    And no unit has a section id containing a blank line's index
    And each unit's parent_section_id is nil, matching the turn-shaped sources

  @consolidation
  Scenario: All turns carry the same synthetic speaker, resolving the drafts' User/Unknown conflict
    Given a transcription file with 5 non-blank lines
    When the loader yields its units
    Then every unit's speaker is "User"
    And every unit's is_user is true
    And the speaker value is defined once as a class constant, not per-line or per-file

  @consolidation
  Scenario: sent_at comes from the file's mtime, not the wall clock
    Given a transcription file whose ref has a known mtime
    When the loader yields its units
    Then every unit's sent_at equals that mtime
    And when the ref has no mtime (a git-tree ref), every unit's sent_at equals the load time instead, matching SubtitleSource's merge_into_turns base-time precedent

  Scenario: Units identify their document the way SubtitleSource's units do
    Given a transcription file with a filesystem path
    When the loader yields its units
    Then every unit's document_key is the ref's path_hint
    And every unit's source_path is the ref's path_hint
    And every unit's metadata includes "file_id" => file_id
    And every unit's heading is nil, because a spoken line has no heading

  Scenario: A ref whose extension is not .txt is rejected
    Given a ref whose extension is ".xyz"
    When the loader yields its units
    Then a SFL::Core::Loaders::Error is raised naming the file and the unsupported extension
    And no unit is yielded

  # STRIDE: Tampering — file content is data, never interpreted
  Scenario: Lines that look like markup or code are emitted as literal text
    Given a transcription file containing a line "```ruby", a line starting with "#", a line "[Speaker 1] hello" and a line containing an HTTP URL
    When the loader yields its units
    Then those lines appear verbatim, stripped, as the text of their own units
    And no line is parsed as markdown, a code fence, a speaker label or a URL by the loader
    And no file content other than the yielded units is written to any log or stderr

  # STRIDE: Denial of service — degenerate input terminates bounded
  Scenario: A file with nothing ingestible raises instead of yielding an empty stream
    Given a zero-byte transcription file
    When the loader yields its units
    Then a SFL::Core::Loaders::Error is raised naming the file
    And the same error is raised for a transcription file containing only blank and whitespace-only lines
    And the ingest boundary rescues that error without aborting the surrounding ingest run
