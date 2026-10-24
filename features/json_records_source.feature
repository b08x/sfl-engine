# Streaming JSON records loader, JsonRecordsSource, registered in the catalog
# under the :claude_export key. The Claude.ai conversations.json
# export is one instance of the shape this loader detects.
#
# Glossary used here (AGENTS.md):
#   document = one whole item: one element of the top-level array that matches
#              the document shape (a conversation, for the Claude export).
#   section  = one element of that document's section list (a message).
#   document_key identifies a document. For the Claude export it is the
#              conversation's own uuid field. Not the file path, not path plus uuid.
#   section_id = "<document_key>#turn-<N>". N counts only the yielded sections
#              of that document, from 0, with no gaps. A message skipped for
#              having no text does not consume a number.
#
# Shape rule (kept small on purpose):
#   1. The file's top-level value is a JSON array. Each element is a record.
#   2. A record is a document record when it is a JSON object with a String
#      "uuid" key and an Array "chat_messages" key.
#      document_key = uuid; sections = the elements of chat_messages, in order;
#      section text = the element's "text" key.
#   3. Anything else is skipped with a warning and the rest of the file
#      continues. Reasons: not_a_record, no_document_key, no_section_list.
#   4. If the array has at least one record and no document record, one
#      warning, reason no_known_shape, is logged and nothing is yielded.
#   5. A document record whose uuid contains "#" or a line break is skipped
#      with a warning, reason invalid_document_key. The rest of the file
#      continues. No section id is built from that uuid.
#   6. A document record whose uuid already appeared earlier in the same file
#      is skipped with a warning, reason duplicate_document_key. The first
#      record is kept. The rest of the file continues.
#   Skips under 5 and 6 are listed under "skipped" in the batch run summary.
#   They are not failed files and are not redundant.
#
# Decisions applied (made by the user, not re-opened here):
#   - The loader streams the file. Memory is the only bound on size. No size cap.
#   - document_key is the conversation uuid. Two files with the same uuid are
#     one document.
#   - section_id is tied to the parent: "<uuid>#turn-N", N counts that
#     conversation's messages from 0.
#   - Each file is all-or-nothing. Its units are written inside one database
#     transaction. A parse error or truncation rolls that file back, so no unit
#     from the failed file is kept.
#   - Single-file run: the failure raises an error naming the file and
#     byte_offset. Nothing from that file is ingested.
#   - Batch run: the failure is recorded as a failed file in the run summary,
#     with file and byte_offset. The batch continues with the other files.
#   - Redundancy exception: if every conversation uuid in the failed file also
#     appears in an intact file of the same batch, the failed file is skipped
#     with a warning (reason redundant_with_intact_file, with file and
#     byte_offset) and is not counted as failed. If any uuid appears only in the
#     failed file, it stays a failure.
#
# Assumptions, each listed as a question in the report:
#   - A message skipped for empty text does not consume an N. When the middle
#     of three messages has no text, the third yields turn-1.
#   - A conversation with zero messages yields no units and no warning.
#   - Top-level value that is not an array: a failure under the rules above,
#     reason not_an_array, nothing ingested from the file.
#   - Class name SFL::Core::Loaders::JsonRecordsSource; file lib/sfl/core/loaders/json_records_source.rb.
#
# Logging: Ports::Logger, keyword fields only. component "JsonRecordsSource",
# file = basename of the file, reason = one of the values named in this file,
# byte_offset = Integer (parse errors, truncation and redundant skips), record_index = Integer
# (per-record warnings), document_key = String (duplicate_document_key and
# invalid_document_key warnings only). document_key is the uuid, sanitized:
# each carriage return or line feed is replaced by one space, then the value
# is cut to 64 characters. No warning carries message text or a conversation
# name. Only the two uuid warnings carry a uuid.
#
# STRIDE gate (specifier): two trust-boundary crossings.
#   (a) file content, read as untrusted JSON      -> 7 misuse scenarios
#   (b) the file path (the ref)                   -> 2 misuse scenarios
# The loader makes no network call and runs no external process.

Feature: A streaming JSON records loader yields one document per conversation record and one section per message

  A top-level JSON array is streamed element by element. Each record with a
  String "uuid" and a "chat_messages" array is a document. Each message in
  that array with a non-empty "text" is one section unit. Units are yielded
  in file order.

  Background:
    Given a JSON file named "conversations.json" whose top-level value is written as given in each scenario
    And a file ref for that path built with the helper the loader specs use (spec/support/file_ref_helper.rb)
    And a loader constructed as SFL::Core::Loaders::JsonRecordsSource.new(ref)

  Scenario: Streaming yields one unit per message, keyed by the conversation uuid
    Given the array holds conversation "c-alpha" with messages "first" (human), "second" (assistant) and "third" (human), followed by conversation "c-beta" with one message "fourth" (human)
    When the loader yields its units
    Then exactly 4 units are yielded, each a SFL::Core::Types::Unit
    And the section ids are "c-alpha#turn-0", "c-alpha#turn-1", "c-alpha#turn-2" and "c-beta#turn-0", in that order
    And units 0, 1 and 2 have document_key "c-alpha"
    And unit 3 has document_key "c-beta"
    And units 0 and 2 have is_user true, and unit 1 has is_user false
    And no warning is logged

  Scenario: The file is read without loading it whole
    Given a generated file of about 64 MiB holding 2,000 conversations of 2 messages each
    And a budget of 16 MiB, measured as the growth of the process's peak resident memory during the load
    When the loader yields its units and the caller discards each unit after reading its section id
    Then exactly 4,000 units are yielded
    And the peak resident memory growth during the load is under 16 MiB

  Scenario: Message text comes from the text field
    Given a message whose "text" is "from the text field" and whose "content" holds one block of type "text" with text "from the content block"
    When the loader yields its units
    Then exactly 1 unit is yielded
    And that unit's text is exactly "from the text field"

  Scenario Outline: A message with empty or missing text is skipped with a warning, the numbering has no gap, and the rest continues
    Given conversation "c-alpha" with messages "one", <middle_message> and "three"
    And conversation "c-beta" with one message "four"
    When the loader yields its units
    Then exactly 3 units are yielded
    And the section ids are "c-alpha#turn-0", "c-alpha#turn-1" and "c-beta#turn-0"
    And the texts of those units are "one", "three" and "four", in that order
    And exactly one warning is logged with keyword fields component "JsonRecordsSource", file "conversations.json" and reason "<reason>"
    And the warning contains no message text and no uuid

    Examples:
      | middle_message        | reason       |
      | text "" (empty)       | text_empty   |
      | no "text" key         | text_missing |
      | text null             | text_missing |

  Scenario: A message whose text is a number has no text, is skipped with a warning, and the rest continues
    Given conversation "c-alpha" with messages "one", a message whose "text" is 42, and "three"
    When the loader yields its units
    Then exactly 2 units are yielded
    And the section ids are "c-alpha#turn-0" and "c-alpha#turn-1"
    And exactly one warning is logged with reason "text_empty"

  Scenario: When the first message has empty text, the second message is turn-0
    Given conversation "c-alpha" with messages "" (empty) and "second"
    When the loader yields its units
    Then exactly 1 unit is yielded
    And its section id is "c-alpha#turn-0" and its text is "second"
    And exactly one warning is logged with keyword fields component "JsonRecordsSource", file "conversations.json" and reason "text_empty"

  Scenario Outline: A non-String text yields its String values joined with a newline, and does not raise
    Given conversation "c-alpha" with one message whose "text" is <text_value>
    When the loader yields its units
    Then no SFL::Core::Loaders::Error is raised
    And exactly 1 unit is yielded
    And that unit's text is "<expected_text>"
    And no warning is logged

    Examples:
      | text_value                                       | expected_text                           |
      | ["first part", "second part"]                    | first part, one line break, second part |
      | {"count": 2, "outer": {"inner": "nested text"}}  | nested text                             |

  Scenario: A message of 5 MiB is yielded whole, with its full text
    Given conversation "c-alpha" with a first message whose "text" is 5 MiB (5,242,880 bytes) of ordinary text, followed by a message "after"
    When the loader yields its units
    Then no SFL::Core::Loaders::Error is raised
    And exactly 2 units are yielded
    And the first unit's text equals the 5 MiB text byte for byte, with a bytesize of 5,242,880
    And the second unit's text is "after" and its section id is "c-alpha#turn-1"
    And no warning is logged

  # Shape detection. A record that is not a document record is skipped with a
  # warning. The rest of the file continues.
  Scenario Outline: A record that does not match the document shape is skipped with a warning, and the rest continues
    Given a top-level array whose first element is <record>, followed by conversation "c-beta" with one message "after"
    When the loader yields its units
    Then exactly 1 unit is yielded
    And the section id is "c-beta#turn-0" and its text is "after"
    And exactly one warning is logged with keyword fields component "JsonRecordsSource", file "conversations.json", record_index 0 and reason "<reason>"
    And the warning contains no message text and no uuid

    Examples:
      | record                                                  | reason            |
      | {"name": "no uuid", "chat_messages": []}                | no_document_key   |
      | {"uuid": 42, "chat_messages": []}                       | no_document_key   |
      | {"uuid": "c-alpha", "name": "no message list"}          | no_section_list   |
      | {"uuid": "c-alpha", "chat_messages": "not an array"}    | no_section_list   |
      | "a string element"                                      | not_a_record      |

  Scenario: A top-level array with records and no document record yields nothing and warns once for the file
    Given a top-level array holding only the records {"name": "a"} and {"name": "b"}
    When the loader yields its units
    Then no unit is yielded
    And exactly one warning is logged with keyword fields component "JsonRecordsSource", file "conversations.json" and reason "no_known_shape"

  Scenario Outline: A top-level value that is not an array is a failure with reason not_an_array, and nothing is ingested from the file
    Given a file whose content is "<content>"
    When I ingest "conversations.json" as a single-file run
    Then an SFL::Core::Loaders::Error is raised with reason "not_an_array" and file "conversations.json"
    And no document row and no section row exists for the file

    Examples:
      | content                                                        |
      | {"conversations": [{"uuid": "c-alpha", "chat_messages": []}]} |
      | "a string, not an array"                                       |

  Scenario: A batch with a file whose top-level value is not an array lists it as failed with reason not_an_array, and the batch continues
    Given file "export-a.json" holds conversation "c-alpha" with messages "one" and "two", fully written
    And file "export-b.json" whose content is {"conversations": [{"uuid": "c-beta", "chat_messages": []}]}
    When I run a batch over "export-b.json" then "export-a.json"
    Then the batch run summary lists "export-b.json" as failed with reason "not_an_array"
    And the section rows "c-alpha#turn-0" and "c-alpha#turn-1" from "export-a.json" are present
    And no document row exists for "c-beta"

  Scenario: An empty top-level array yields nothing and logs nothing
    Given a file whose content is "[]"
    When the loader yields its units
    Then no unit is yielded
    And no warning is logged

  Scenario: A conversation with zero messages yields no units and no warning
    Given conversation "c-empty" with no messages, followed by conversation "c-beta" with one message "after"
    When the loader yields its units
    Then exactly 1 unit is yielded
    And the section id is "c-beta#turn-0"
    And no unit has document_key "c-empty"
    And no warning is logged

  # STRIDE: Tampering with the section key space, trust-boundary crossing (a).
  # Misuse scenario 1 of 6. Two conversations in one file with the same uuid.
  # The second is not allowed to replace or merge into the first.
  Scenario: A second conversation with a uuid already seen in the file is skipped with a warning, and the first is kept
    Given conversation "c-alpha" with messages "first-a" and "second-a"
    And then conversation "c-alpha" again with messages "first-b" and "second-b" and "third-b"
    When the loader yields its units
    Then exactly 2 units are yielded
    And the texts of those units are "first-a" and "second-a"
    And the section ids are "c-alpha#turn-0" and "c-alpha#turn-1"
    And no unit has text "first-b", "second-b" or "third-b"
    And exactly one warning is logged with keyword fields component "JsonRecordsSource", file "conversations.json", record_index 1, reason "duplicate_document_key" and document_key "c-alpha"

  Scenario: A conversation uuid repeated within one file is listed as skipped in the run summary, not as failed or redundant
    Given file "export-a.json" holds conversation "c-alpha" with messages "one" and "two", then conversation "c-alpha" again with message "three", then conversation "c-beta" with message "four", fully written
    When I run a batch over "export-a.json"
    Then the batch run summary counts 0 failed files and 0 redundant files
    And the batch run summary lists one skipped entry for "export-a.json" with reason "duplicate_document_key" and record_index 1
    And exactly one warning is logged with keyword fields component "JsonRecordsSource", file "export-a.json", record_index 1, reason "duplicate_document_key" and document_key "c-alpha"
    And the warning contains no message text and no conversation name
    And the section rows "c-alpha#turn-0", "c-alpha#turn-1" and "c-beta#turn-0" from "export-a.json" are present, with texts "one", "two" and "four"
    And no row holds the text "three"

  # Deduplication across files. Assumes the store upserts sections by section_id
  # and documents by document_key, as the ingest path already does.
  Scenario: The same conversation uuid in two files is one document, and re-ingesting updates it in place
    Given file "export-a.json" holds conversation "c-alpha" with messages "one" and "two"
    And file "export-b.json" holds conversation "c-alpha" with messages "one" and "two, revised"
    When I ingest "export-a.json", then "export-b.json", then "export-a.json" again
    Then exactly one document row exists with document_key "c-alpha"
    And exactly two section rows exist for "c-alpha", with section ids "c-alpha#turn-0" and "c-alpha#turn-1"
    And the document row's id is the same after each ingest
    And each section row keeps its surrogate id after each ingest
    And the section row "c-alpha#turn-1" has the text "two, revised" after the second ingest
    And after the third ingest the section row "c-alpha#turn-1" has the text "two"
    And no section row or document row is created or deleted by the second or third ingest beyond the first ingest's rows

  # Stale sections. After a batch run writes every file, each document an intact file holds is reconciled once:
  # its stored sections the run did not write are removed. A document named by a failed file, or by no file, keeps its sections.
  Scenario: A batch run removes a section that a re-ingested document no longer has, and keeps the surviving sections' ids
    Given file "export-a.json" holds conversation "c-alpha" with messages "one", "two" and "three", fully written
    And file "export-b.json" holds conversation "c-alpha" with messages "one" and "two", fully written
    When batch run "export-a.json" is followed by batch run "export-b.json"
    Then the batch run summary counts 0 failed files
    And the batch run summary reports stale_removed 1
    And the section rows "c-alpha#turn-0" and "c-alpha#turn-1" from "export-b.json" are present, with texts "one" and "two"
    And the section "c-alpha#turn-2" is absent
    And the section ids "c-alpha#turn-0" and "c-alpha#turn-1" are unchanged by the second run
    And the document row "c-alpha" has section_count 2

  Scenario: A batch run never removes sections of a document that the run does not hold
    Given file "export-a.json" holds conversation "c-alpha" with messages "one" and "two", followed by conversation "c-beta" with messages "three" and "four", fully written
    And file "export-b.json" holds conversation "c-alpha" with message "one", fully written
    When batch run "export-a.json" is followed by batch run "export-b.json"
    Then the batch run summary reports stale_removed 1
    And the section "c-alpha#turn-1" is absent
    And the section rows "c-beta#turn-0" and "c-beta#turn-1" from "export-a.json" are present, with texts "three" and "four"

  Scenario: A failed file in a batch does not remove sections of the document it names
    Given file "export-a.json" holds conversation "c-alpha" with messages "one", "two" and "three", fully written
    And file "export-b.json" holds conversation "c-alpha" with message "one", fully written, then conversation "c-omega" cut off after its first message's opening brace, and the file ends there
    When batch run "export-a.json" is followed by batch run "export-b.json"
    Then the batch run summary lists "export-b.json" as failed with reason "truncated" and byte_offset equal to the file's byte size
    And the batch run summary reports stale_removed 0
    And the section rows "c-alpha#turn-0", "c-alpha#turn-1" and "c-alpha#turn-2" from "export-a.json" are present

  Scenario: Re-ingesting an unchanged file is idempotent
    Given file "export-a.json" holds conversation "c-alpha" with messages "one" and "two"
    When I ingest "export-a.json" twice
    Then the database rows after the second ingest are identical to the rows after the first ingest, except for the ingest timestamp

  # Malformed and truncated files. Each file is all-or-nothing: a failure rolls
  # back every unit of that file. Single-file run: the error names the file and
  # byte_offset. Batch run: the file is listed as failed in the run summary.
  Scenario: A single-file run on a truncated file raises an error that names the file and byte_offset, and ingests nothing from the file
    Given conversation "c-alpha" with messages "one" and "two", fully written
    And then conversation "c-beta" whose "chat_messages" array is cut off after its first message's opening brace, and the file ends there
    When I ingest "conversations.json" as a single-file run
    Then an SFL::Core::Loaders::Error is raised with reason "truncated", file "conversations.json" and byte_offset equal to the file's byte size
    And no document row and no section row exists for "c-alpha" or "c-beta"

  Scenario: A single-file run on a file with a parse error mid-file raises an error with reason parse_error, and ingests nothing from the file
    Given conversation "c-alpha" with messages "one" and "two", fully written
    And then a stray "}" in place of the comma after conversation "c-alpha", followed by conversation "c-beta" with one message "three"
    When I ingest "conversations.json" as a single-file run
    Then an SFL::Core::Loaders::Error is raised with reason "parse_error", file "conversations.json" and byte_offset equal to the offset of that "}"
    And no document row and no section row exists for "c-alpha" or "c-beta"

  Scenario: A batch with a truncated file whose uuids are all unique to it continues, lists the file as failed, and stores none of its units
    Given file "export-a.json" holds conversation "c-alpha" with messages "one" and "two", fully written
    And file "export-b.json" holds conversation "c-beta" with message "three", fully written, then conversation "c-gamma" cut off after its first message's opening brace, and the file ends there
    When I run a batch over "export-b.json" then "export-a.json"
    Then the batch run summary lists "export-b.json" as failed with reason "truncated" and byte_offset equal to the file's byte size
    And the section rows "c-alpha#turn-0" and "c-alpha#turn-1" from "export-a.json" are present
    And no document row and no section row exists for "c-beta" or "c-gamma"
    And no warning with reason "redundant_with_intact_file" is logged

  Scenario: A batch with a truncated file whose every uuid also appears in an intact file skips it with a warning and does not count it as failed
    Given file "export-a.json" holds conversation "c-alpha" with messages "one" and "two", followed by conversation "c-beta" with message "three", fully written
    And file "export-b.json" holds conversation "c-alpha" with messages "one" and "two", fully written, then conversation "c-beta" cut off after its first message's opening brace, and the file ends there
    When I run a batch over "export-b.json" then "export-a.json"
    Then the batch run summary counts 0 failed files
    And exactly one warning is logged with keyword fields component "JsonRecordsSource", file "export-b.json", byte_offset equal to the file's byte size and reason "redundant_with_intact_file"
    And the warning contains no message text and no uuid
    And the section rows "c-alpha#turn-0", "c-alpha#turn-1" and "c-beta#turn-0" from "export-a.json" are present
    And the store holds exactly the rows that a batch over "export-a.json" alone produces

  Scenario: A batch with a truncated file where one uuid is unique to it is counted as failed, even though the other uuid appears in an intact file
    Given file "export-a.json" holds conversation "c-alpha" with messages "one" and "two", fully written
    And file "export-b.json" holds conversation "c-alpha" with messages "one" and "two", fully written, then conversation "c-omega" cut off after its first message's opening brace, and the file ends there
    When I run a batch over "export-b.json" then "export-a.json"
    Then the batch run summary lists "export-b.json" as failed with reason "truncated" and byte_offset equal to the file's byte size
    And no warning with reason "redundant_with_intact_file" is logged
    And the store holds exactly the rows that a batch over "export-a.json" alone produces
    And no document row and no section row exists for "c-omega"

  # STRIDE: Tampering and Denial of service on file content, trust-boundary
  # crossing (a). Misuse scenario 2 of 6. A raw control character is invalid
  # JSON. The loader fails the file and ingests nothing from it.
  Scenario: A message whose text contains a raw U+0001 control character fails the file, and nothing from the file is ingested
    Given conversation "c-alpha" with messages "one" and a message whose "text" contains a raw U+0001 control character, then message "three"
    When I ingest "conversations.json" as a single-file run
    Then an SFL::Core::Loaders::Error is raised with reason "parse_error", file "conversations.json" and an integer byte_offset
    And no document row and no section row exists for "c-alpha"

  # STRIDE: Denial of service on file content, trust-boundary crossing (a).
  # Misuse scenario 3 of 6. The expected containment is a unit or a warning.
  # A stack overflow that terminates the process is not allowed.
  Scenario: A text value nested 100,000 arrays deep is contained, not a crash
    Given conversation "c-alpha" with a message whose "text" is 100,000 nested arrays, the innermost holding "deep"
    When the loader yields its units
    Then the loader either yields exactly 1 unit whose text is "deep", or raises an error with reason "parse_error", file "conversations.json" and an integer byte_offset, and yields no unit
    And the process does not terminate with a stack overflow error

  # STRIDE: Spoofing and Tampering of the log, trust-boundary crossing (a).
  # Misuse scenario 4 of 6. A conversation name with a line break is metadata.
  # It must not reach a log line.
  Scenario: A conversation name containing a line break cannot split a log line
    Given conversation "c-alpha" named "Harmless\nlevel=error FORGED", with a first message whose "text" is "" and a second message "two"
    When the loader yields its units
    Then exactly 1 unit is yielded, with section id "c-alpha#turn-0"
    And exactly one warning is logged with reason "text_empty"
    And no warning message or field contains a line break character
    And no warning message or field contains the text "FORGED"
    And the unit's metadata "conversation_title" is "Harmless\nlevel=error FORGED", unchanged

  # STRIDE: Tampering with section ids, trust-boundary crossing (a).
  # Misuse scenario 5 of 6. A uuid that contains "#" or a line break would
  # make a section_id ambiguous or split a log line. The record is rejected.
  Scenario Outline: A uuid containing "#" or a line break is rejected with a warning, and no section id is built from it
    Given conversation with uuid "<uuid>" and messages "one" and "two", followed by conversation "c-beta" with one message "after"
    When the loader yields its units
    Then exactly 1 unit is yielded, with document_key "c-beta" and text "after"
    And no unit has a section id containing "<uuid_fragment>"
    And exactly one warning is logged with keyword fields component "JsonRecordsSource", file "conversations.json", record_index 0, reason "invalid_document_key" and document_key "<logged_key>"
    And no warning message or field contains a line break character

    Examples:
      | uuid            | uuid_fragment | logged_key     |
      | c-alpha#turn-9  | #turn-9       | c-alpha#turn-9 |
      | c-alpha\nx      | line break    | c-alpha x      |

  Scenario: An invalid uuid is listed as skipped in the run summary, not as failed or redundant
    Given file "export-a.json" holds conversation "c-alpha#turn-9" with messages "one" and "two", then conversation "c-beta" with message "after", fully written
    When I run a batch over "export-a.json"
    Then the batch run summary counts 0 failed files and 0 redundant files
    And the batch run summary lists one skipped entry for "export-a.json" with reason "invalid_document_key" and record_index 0
    And exactly one warning is logged with keyword fields component "JsonRecordsSource", file "export-a.json", record_index 0, reason "invalid_document_key" and document_key "c-alpha#turn-9"
    And the section row "c-beta#turn-0" from "export-a.json" is present with text "after"
    And no section row has a section id containing "c-alpha"

  # STRIDE: Spoofing and Tampering of the log through the uuid, trust-boundary
  # crossing (a). Misuse scenario 7 of 7. A uuid with a line break is logged
  # sanitized. The line break must not start a new log line.
  Scenario: An invalid uuid whose value contains a line break does not split the log line
    Given conversation with uuid "c-alpha" followed by a line feed and "FORGED level=error", with messages "one" and "two", followed by conversation "c-beta" with one message "after"
    When the loader yields its units and the warnings are written to the stderr log target
    Then exactly 1 unit is yielded, with document_key "c-beta"
    And exactly one warning is logged with reason "invalid_document_key" and document_key "c-alpha FORGED level=error"
    And the warning is written as exactly one line
    And no warning message or field contains a line break character

  Scenario: An invalid uuid longer than 64 characters is logged cut to 64 characters
    Given conversation with uuid "c-" followed by 100 "a" characters and then "#", with message "one", followed by conversation "c-beta" with one message "after"
    When the loader yields its units
    Then exactly one warning is logged with reason "invalid_document_key"
    And its document_key is the first 64 characters of that uuid
    And no unit has that uuid as document_key

  # STRIDE: Tampering through file content, trust-boundary crossing (a).
  # Misuse scenario 6 of 6. Message text is data. A text that looks like a
  # record boundary or a second record stays inside its unit.
  Scenario: A message whose text contains a JSON record that looks like a new conversation stays inside its unit
    Given conversation "c-alpha" with one message whose "text" is the string "{\"uuid\": \"c-injected\", \"chat_messages\": []}"
    When the loader yields its units
    Then exactly 1 unit is yielded, with document_key "c-alpha"
    And its text is the literal string {"uuid": "c-injected", "chat_messages": []}
    And no unit has document_key "c-injected"
    And no warning is logged

  # STRIDE: Information disclosure and path abuse, trust-boundary crossing (b):
  # the file path. Misuse scenario 1 of 2.
  Scenario: The loader opens only the file named by its ref
    Given a file ref for "exports/conversations.json" inside a directory that also holds "secrets.json"
    And file-open and directory-listing calls are recorded during the load
    When the loader yields its units
    Then the only path opened is the ref's path
    And no directory is listed
    And "secrets.json" is never opened, read or stat'd
    And the loader gets file content only through the ref

  # STRIDE: Spoofing and Tampering of the log through the file name, trust-
  # boundary crossing (b). Misuse scenario 2 of 2. A basename with a line break
  # must not split a warning line.
  Scenario: A file name containing a line break cannot split a log line
    Given a file named "bad\nname.json" whose only conversation has a message whose "text" is ""
    When the loader yields its units
    Then exactly one warning is logged with reason "text_empty"
    And the warning field "file" is "bad name.json"
    And no warning message or field contains a line break character
