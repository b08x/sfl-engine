# SillyTavern group-chat loader: acceptance scenarios for
# SFL::Core::Loaders::SillyTavernSource (lib/sfl/core/loaders/sillytavern_source.rb).
#
# Glossary used here:
#   document = one whole JSONL session file (one chat session).
#   section  = one turn (one emitted unit) in that file. Section ids are
#              "#{file_id}#turn-#{i}", i counting emitted units from 0.
#
# Time zone decision: send_date strings carry no zone (for example
# "June 19, 2024 2:22pm"). They are US Eastern wall-clock time. The loader
# converts them to UTC; sent_at is a UTC Time (the database runs in UTC).
# Offset rule, implemented in plain Ruby with no tzinfo gem:
#   EDT (UTC-4) from the second Sunday of March at 2:00 local time to the
#   first Sunday of November at 2:00 local time; EST (UTC-5) otherwise.
# Boundary dates used by the scenarios:
#   spring-forward: 2024-03-10 (second Sunday of March 2024)
#   fall-back:      2024-11-03 (first Sunday of November 2024)
# Wall-clock times inside the skipped hour (2:00 to 2:59 on 2024-03-10) and
# the repeated hour (1:00 to 1:59 on 2024-11-03) have no scenario.
#
# System records: a record with "is_system" true and a String mes is skipped
# without a warning. A system record with a non-String mes is read like any
# other record and is a unit if it has text. The header is usually the first
# record, but not always: two sample files have no system record at all.
#
# Unusable send_date: the unit is still emitted, with sent_at nil, and a
# warning is logged through Ports::Logger with keyword fields component,
# file, line and reason. reason is a fixed code, never the raw send_date text.
#
# STRIDE gate (specifier): three trust-boundary crossings.
#   (a) session file content is untrusted data           -> 3 misuse scenarios
#   (b) send_date parsing                                 -> 1 misuse scenario
#   (c) file path                                         -> 1 misuse scenario
# The loader makes no network call and runs no external process; no
# scenario is needed for those crossings.
#
# Malformed-line rule: a physical line that is not valid JSON raises
# SillyTavernSource::SourceError naming the file and line, and yields no
# partial units.
#
# Line rule: every physical line is one complete JSON record. A line break
# inside a message is stored as the two characters \n in the JSON string.
Feature: SillyTavern group-chat loader turns session JSONL into turns

  A SillyTavern group-chat export is a JSONL file: one complete JSON record
  per physical line. A message containing a line break stores it as the
  two characters \n inside the JSON string, so the record stays on one
  line. A system record (is_system true) with a String mes is never a unit.
  A system record with a non-String mes is a unit if it has text. The loader
  reads the whole file and yields one SFL::Core::Types::Unit per record that
  yields text, in file order. The
  constructor shape is (ref, file_id:), following the other sources in
  lib/sfl/core/loaders/. Fatal cases raise SillyTavernSource::SourceError, a
  subclass of SFL::Core::Loaders::Error, which the ingest boundary rescues.

  Background:
    Given a SillyTavern group-chat session file written as JSONL
    And a file ref for that path built with the helper the loader specs use (spec/support/file_ref_helper.rb)
    And a loader constructed as SFL::Core::Loaders::SillyTavernSource.new(ref, file_id: "st-session")

  Scenario: A system record with a String mes is never a unit and never produces a warning
    Given a session file whose first record is the system header with "name" "SillyTavern System", "is_system" true, "is_group" true, and "mes" "Group chat created..."
    And the file has a second system record with "is_system" true between its turn records
    And the file has 3 non-system turn records besides those two system records
    When the loader yields its units
    Then exactly 3 units are yielded, each a SFL::Core::Types::Unit
    And no unit has text "Group chat created..."
    And no unit has speaker "SillyTavern System"
    And no warning is logged for either system record

  Scenario: Each turn record is one unit, in file order, with section ids contiguous from turn-0
    Given a session file with turn records from "Steve", "Mason" and "Robert" in that order
    When the loader yields its units
    Then the units' section ids are "st-session#turn-0", "st-session#turn-1" and "st-session#turn-2"
    And the units' speakers are "Steve", "Mason" and "Robert" in that order
    And each unit's parent_section_id is nil
    And each unit's heading is nil

  Scenario Outline: Speaker is the record's name and is_user is the record's is_user flag
    Given a session file with a turn record whose "name" is "<name>" and whose "is_user" is <is_user>
    When the loader yields its units
    Then the unit's speaker is "<name>"
    And the unit's is_user is <is_user>

    Examples:
      | name                | is_user |
      | Robert              | true    |
      | Word Retrieval Unit | false   |
      | Ameila              | false   |

  Scenario Outline: send_date is US Eastern wall-clock time, converted to UTC with the offset in force on that date
    Given a session file whose mtime is 2026-10-24T09:00:00Z
    And a turn record with "send_date" "<send_date>"
    When the loader yields its units
    Then that unit's sent_at is <sent_at_utc>
    And that unit's sent_at is a Time whose UTC offset is zero
    And that unit's sent_at does not equal the file mtime

    Examples:
      | send_date                | sent_at_utc          | offset in force |
      | June 19, 2024 2:22pm     | 2024-06-19T18:22:00Z | UTC-4 (EDT)     |
      | January 15, 2024 2:22pm  | 2024-01-15T19:22:00Z | UTC-5 (EST)     |

  Scenario: The spring-forward boundary switches from EST to EDT at 2:00 local time on 2024-03-10
    Given a session file with turn records whose "send_date" values are "March 10, 2024 1:59am" and "March 10, 2024 3:00am" in that order
    When the loader yields its units
    Then the first unit's sent_at is 2024-03-10T06:59:00Z, which is UTC-5
    And the second unit's sent_at is 2024-03-10T07:00:00Z, which is UTC-4
    And the difference between the two units' sent_at values is 60 seconds, although the wall clock advanced 61 minutes

  Scenario: The fall-back boundary switches from EDT to EST at 2:00 local time on 2024-11-03
    Given a session file with turn records whose "send_date" values are "November 3, 2024 12:59am" and "November 3, 2024 2:00am" in that order
    When the loader yields its units
    Then the first unit's sent_at is 2024-11-03T04:59:00Z, which is UTC-4
    And the second unit's sent_at is 2024-11-03T07:00:00Z, which is UTC-5
    And the difference between the two units' sent_at values is 7260 seconds

  Scenario: A message whose decoded text contains a line break is one unit whose text has that line break
    Given a session file with these physical lines:
      """
      {"name":"Hobbes","is_user":false,"is_system":false,"send_date":"June 15, 2024 6:35pm","mes":"First line\nsecond line"}
      {"name":"Steve","is_user":false,"is_system":false,"send_date":"June 15, 2024 6:36pm","mes":"Next turn"}
      """
    When the loader yields its units
    Then exactly 2 units are yielded, one per physical line
    And the first unit's text is "First line", then one line break character, then "second line"
    And the first unit's section id is "st-session#turn-0"
    And the second unit's section id is "st-session#turn-1"

  Scenario: A session file whose last line has no trailing line break is loaded in full
    Given a session file with a system header, then two turn records "first" and "last, no line break", where the final record has no line break after it
    When the loader yields its units
    Then exactly 2 units are yielded
    And the last unit's section id is "st-session#turn-1"
    And the last unit's text is "last, no line break"

  # STRIDE: Tampering and Denial of service through a malformed line,
  # trust-boundary crossing (a). The loader raises rather than skipping the line.

  Scenario: A line that is not valid JSON raises an error naming the file and line, with no partial units
    Given a session file whose physical line 3 is '{"name":"Steve","is_user":false,"send_date":"June 15, 2024 6:35pm","mes":"never closed'
    And lines 1, 2, 4 and 5 are valid turn records
    When the loader yields its units
    Then exactly one SFL::Core::Loaders::Error is raised
    And the error's file field is the basename of the session file
    And the error's line field is 3, the physical line that is not valid JSON
    And no unit is yielded from any line of that file, because the whole file is parsed before the first unit is yielded
    And the ingest boundary rescues the error without aborting the surrounding ingest run

  Scenario: A ref whose extension is not .jsonl is rejected
    Given a ref whose path ends in ".json"
    When the loader yields its units
    Then a SFL::Core::Loaders::Error is raised naming the file and the unsupported extension
    And no unit is yielded

  Scenario Outline: A file with nothing ingestible raises instead of yielding an empty stream
    Given a session file whose content is "<content>"
    When the loader yields its units
    Then a SFL::Core::Loaders::Error is raised naming the file
    And no unit is yielded

    Examples:
      | content                                                                                                         |
      |                                                                                                                 |
      | {"name":"SillyTavern System","is_user":false,"is_system":true,"is_group":true,"mes":"Group chat created..."}    |

  Scenario: Units carry document_key, source_path, file_id and the source file name
    Given a session file at a filesystem path whose basename is "2024-6-15@18h35m15s.jsonl"
    And the loader was constructed with file_id "st-session"
    When the loader yields its units
    Then every unit's document_key is the ref's path_hint
    And every unit's source_path is the ref's path_hint
    And every unit's metadata equals {"file_id" => "st-session", "source_file" => "2024-6-15@18h35m15s.jsonl"}

  Scenario Outline: Session file names with spaces, "#" and "@" load
    Given a session file named "<file_name>" containing 2 turn records
    When the loader yields its units
    Then exactly 2 units are yielded
    And every unit's metadata "source_file" is "<file_name>"

    Examples:
      | file_name                                      |
      | Branch #210 - 2024-6-19@16h23m07s.jsonl        |
      | Checkpoint #4 - 2024-6-17@12h34m44s.jsonl      |
      | existential docker - 2024-6-19@16h55m50s.jsonl |

  # Five sample sessions in output/eval/_src/sim_chats/. Expected unit
  # counts are non-system records. Two files have no system record, so
  # every record is a unit there: 713 and 62, not 712 and 61.
  # Every line of these files is one complete JSON record, so these scenarios check counting.
  Scenario Outline: Sample session files yield one unit per non-system record
    Given the sample session file "<file_name>"
    When the loader yields its units
    Then exactly <units> units are yielded
    And the last unit's section id is "st-session#turn-<last_index>"
    And every unit's speaker is a non-empty String
    And every unit's sent_at is a Time, not nil

    Examples:
      | file_name                                | units | last_index |
      | Branch #210 - 2024-6-19@16h23m07s.jsonl  | 270   | 269        |
      | Branch #393 - 2024-6-16@03h31m11s.jsonl  | 713   | 712        |
      | 2024-6-15@18h35m15s.jsonl                | 174   | 173        |
      | 2024-6-15@20h21m29s.jsonl                | 114   | 113        |
      | 2024-6-19@11h34m27s.jsonl                | 62    | 61         |

  Scenario: A branch or checkpoint of another session is loaded as its own document
    Given the sample session file "Branch #393 - 2024-6-16@03h31m11s.jsonl"
    And the sample session file "Checkpoint #4 - 2024-6-17@12h34m44s.jsonl"
    When the loader yields units for each file under its own file_id
    Then each file yields its own units with document_key set to that file's path_hint
    And the two document_keys are different
    And no unit is dropped or merged because another file has the same turn count or the same content
    And the loader itself performs no deduplication across files

  # STRIDE: Tampering and Denial of service on file content, trust-boundary
  # crossing (a). The file is untrusted data. Malformed JSON is covered by the
  # scenario above. Message size is not checked.
  Scenario Outline: Untrusted file content is rejected or kept whole, never partially emitted
    Given a session file containing <case>
    When the loader yields its units
    Then <outcome>

    Examples:
      | case                                                                         | outcome                                                                                                                                  |
      | one message whose mes contains a raw U+0001 control character                | a SFL::Core::Loaders::Error is raised naming the file and the line; no unit is yielded from that file                                    |
      | one message of 73 KB of ordinary text, the largest sample message            | exactly one unit is yielded whose text equals the mes value byte for byte                                                                |

  # STRIDE: Tampering. Message text is data. Markup, code fences and URLs
  # are never interpreted. Trust-boundary crossing (a).
  Scenario: Message text that looks like markup, a code fence or a URL is emitted verbatim
    Given a turn record whose mes is "<b>bold</b> ```ruby\nputs 1\n``` *action* https://example.invalid/x?y=1"
    When the loader yields its units
    Then that unit's text is exactly "<b>bold</b> ```ruby\nputs 1\n``` *action* https://example.invalid/x?y=1"
    And the loader does not fetch the URL or any other network address
    And no part of the message text is written to stderr or to any log field other than the unit's text

  # The unusable-send_date rule (approved): keep the unit, nil sent_at,
  # warn with keyword fields, continue. No other unit is affected.
  Scenario Outline: An unusable send_date keeps its unit with sent_at nil, logs one warning, and leaves the other units unchanged
    Given a session file with three turn records, where the record at line 2 has <send_date_clause>
    And the records at lines 1 and 3 have send_date "June 15, 2024 6:35pm" and "June 15, 2024 6:36pm"
    When the loader yields its units
    Then no SFL::Core::Loaders::Error is raised
    And exactly 3 units are yielded, each a SFL::Core::Types::Unit
    And the unit at line 2 has sent_at nil
    And the units at lines 1 and 3 have sent_at values 2024-06-15T22:35:00Z and 2024-06-15T22:36:00Z
    And exactly one warning is logged through Ports::Logger with keyword fields component "SillyTavernSource", file equal to the basename of the session file, line 2, and reason "<reason>"
    And the warning's message string contains neither the send_date value nor the file path

    Examples:
      | send_date_clause                 | reason                |
      | send_date "yesterday"            | send_date_unparseable |
      | send_date "June 31, 2024 2:22pm" | send_date_unparseable |
      | send_date "2024-06-19T14:22:00Z" | send_date_unparseable |
      | send_date ""                     | send_date_unparseable |
      | no send_date key                 | send_date_missing     |

  # STRIDE: Tampering and Spoofing of the timestamp, trust-boundary
  # crossing (b). A crafted send_date must not raise, must not invent a time,
  # and must warn with keyword fields only.
  Scenario: A crafted send_date cannot raise, invent a time, or inject text into the log
    Given a turn record at line 2 whose "send_date" is a valid-looking date "June 19, 2024 2:22pm", then a line break, then the text "level=error forged entry"
    And the records at lines 1 and 3 have valid send_date values
    When the loader yields its units
    Then no SFL::Core::Loaders::Error is raised
    And the unit at line 2 has sent_at nil, so no time is taken from the valid-looking prefix
    And exactly one warning is logged with keyword fields component "SillyTavernSource", file equal to the basename of the session file, line 2, and reason "send_date_unparseable"
    And no log message string and no log field contains the crafted text or any part of it
    And the units at lines 1 and 3 keep their own sent_at values

  # STRIDE: Tampering and Spoofing of the log, trust-boundary crossing (a).
  # A neighbour name with a line break must not split the warning across lines.
  Scenario: A neighbour name containing a line break inside its JSON string cannot split a warning line
    Given a session file whose records are the JSON array:
      """
      [{"name": "Steve", "mes": null}, {"name": "Robert\nFORGED level=error", "mes": "two"}]
      """
    When the loader yields its units
    Then exactly 1 unit is yielded
    And exactly 1 warning is logged, each with reason "mes_missing"
    And the warning fields include {"position": "first", "next_name": "Robert FORGED level=error"}
    And no warning message or field contains a line break character

  # STRIDE: Tampering and Spoofing of the log, trust-boundary crossing (a).
  # A file basename with a line break must not split a warning line.
  Scenario: A session file whose name contains a line break cannot split a warning line
    Given a session file named "bad\nname.jsonl" whose records are the JSON array:
      """
      [{"name": "Steve", "mes": "one"}, {"name": "Robert", "mes": null}, {"name": "Mason", "mes": "three"}]
      """
    When the loader yields its units
    Then exactly 2 units are yielded
    And exactly 1 warning is logged, each with reason "mes_missing"
    And the warning fields include {"file": "bad name.jsonl", "line": 2}
    And every unit's metadata "source_file" is "bad name.jsonl"
    And no warning message or field contains a line break character

  # STRIDE: Information disclosure and path abuse, trust-boundary crossing
  # (c): the file path. The ref layer refuses traversal; this scenario checks
  # the loader's side of the boundary.
  Scenario: The loader opens only the file named by its ref
    Given a file ref for "sessions/Branch #210 - 2024-6-19@16h23m07s.jsonl" inside a directory that also holds "secrets.jsonl"
    And file-open and directory-listing calls are recorded during the load
    When the loader yields its units
    Then the only path opened is the ref's path
    And no directory is listed
    And "secrets.jsonl" is never opened, read or stat'd
    And the loader gets file content only through the ref's read method

  # Non-String mes: the text is the String values inside the mes, joined with
  # a newline. A mes with no text, or a missing mes, skips its record with a
  # warning that carries the neighbouring records' context.
  Scenario: A non-String mes yields its String values joined with a newline
    Given a session file whose records are the JSON array:
      """
      [{"name": "Steve", "mes": ["first part", "second part"]}]
      """
    When the loader yields its units
    Then exactly 1 unit is yielded
    And the first unit's text is "first part", then one line break character, then "second part"
    And no warning is logged

  Scenario: A hash mes yields the String nested under its keys, and the keys are not text
    Given a session file whose records are the JSON array:
      """
      [{"name": "Steve", "mes": {"count": 2, "outer": {"inner": "nested text"}}}]
      """
    When the loader yields its units
    Then exactly 1 unit is yielded
    And that unit's text is exactly "nested text"

  Scenario: A String mes containing an emoji is unchanged
    Given a turn record whose mes is "ok 🎉 done"
    When the loader yields its units
    Then exactly one unit is yielded
    And that unit's text is exactly "ok 🎉 done"
    And no warning is logged

  Scenario: A number mes is warned with reason mes_no_text and skipped, and the loader continues
    Given a session file whose records are the JSON array:
      """
      [{"name": "Steve", "mes": "one"}, {"name": "Mason", "mes": 42}, {"name": "Robert", "mes": "four"}]
      """
    When the loader yields its units
    Then exactly 2 units are yielded
    And exactly 1 warning is logged, each with reason "mes_no_text"
    And the warning fields include {"position": "middle", "previous_name": "Steve", "next_name": "Robert", "previous_is_user": false, "next_is_user": false, "previous_is_system": false, "next_is_system": false}

  Scenario: An empty array mes is warned with reason mes_no_text and skipped
    Given a session file whose records are the JSON array:
      """
      [{"name": "Steve", "mes": "one"}, {"name": "Mason", "mes": []}, {"name": "Robert", "mes": "three"}]
      """
    When the loader yields its units
    Then exactly 2 units are yielded
    And exactly 1 warning is logged, each with reason "mes_no_text"

  Scenario: A missing mes in the middle of the file is warned with reason mes_missing and the loader continues
    Given a session file whose records are the JSON array:
      """
      [{"name": "Steve", "is_user": false, "mes": "one"}, {"name": "Mason", "mes": null}, {"name": "Robert", "is_user": true, "mes": "three"}]
      """
    When the loader yields its units
    Then exactly 2 units are yielded
    And exactly 1 warning is logged, each with reason "mes_missing"
    And the warning fields include {"position": "middle", "previous_name": "Steve", "next_name": "Robert", "previous_is_user": false, "next_is_user": true, "previous_is_system": false, "next_is_system": false}

  Scenario: A missing mes on the first record gives nil for the previous neighbour
    Given a session file whose records are the JSON array:
      """
      [{"name": "Robert", "is_user": true, "mes": null}, {"name": "Steve", "mes": "two"}]
      """
    When the loader yields its units
    Then exactly 1 unit is yielded
    And exactly 1 warning is logged, each with reason "mes_missing"
    And the warning fields include {"position": "first", "previous_name": null, "next_name": "Steve", "previous_is_user": null, "next_is_user": false, "previous_is_system": null, "next_is_system": false}

  Scenario: A missing mes on the last record gives nil for the next neighbour
    Given a session file whose records are the JSON array:
      """
      [{"name": "Steve", "mes": "one"}, {"name": "Robert", "is_user": true, "mes": null}]
      """
    When the loader yields its units
    Then exactly 1 unit is yielded
    And exactly 1 warning is logged, each with reason "mes_missing"
    And the warning fields include {"position": "last", "previous_name": "Steve", "next_name": null, "previous_is_user": false, "next_is_user": null, "previous_is_system": false, "next_is_system": null}

  Scenario: A system record with a non-String mes that has text is a unit
    Given a session file whose records are the JSON array:
      """
      [{"name": "SillyTavern System", "is_system": true, "mes": ["Group", "created"]}, {"name": "Steve", "mes": "one"}]
      """
    When the loader yields its units
    Then exactly 2 units are yielded
    And the first unit's text is "Group", then one line break character, then "created"
    And the first unit's section id is "st-session#turn-0"
    And no warning is logged

  # A message of any size is kept whole. Nothing is truncated or split.
  Scenario: A message of 5 MiB is yielded whole, with its full text
    Given a session file whose first record is a turn record "Steve" whose mes is 5 MiB (5,242,880 bytes) of ordinary text
    And the file has a second turn record "Mason" with mes "after"
    When the loader yields its units
    Then no SFL::Core::Loaders::Error is raised
    And exactly 2 units are yielded
    And the first unit's text equals the 5 MiB mes value byte for byte, with a bytesize of 5,242,880
    And the first unit's section id is "st-session#turn-0"
    And the second unit's text is "after" and its section id is "st-session#turn-1"
    And no warning is logged

  Scenario: A system record with a String mes is still skipped, without raising
    Given a session file whose first record is a system record with a String mes, followed by a turn record "one"
    When the loader yields its units
    Then no SFL::Core::Loaders::Error is raised
    And exactly 1 unit is yielded
    And the first unit's text is "one"
    And no warning is logged

  Scenario: Extracted text from a non-String mes larger than 1 MiB is yielded whole
    Given a session file whose second record has a mes of two strings, each 600 KiB, whose join is over 1 MiB
    When the loader yields its units
    Then no SFL::Core::Loaders::Error is raised
    And exactly 2 units are yielded
    And the second unit's text is the first string, one line break character, then the second string, byte for byte
