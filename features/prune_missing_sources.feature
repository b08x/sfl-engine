# Prune of documents whose source file is gone, the archive timestamp, and
# default retrieval exclusion of archived documents.
#
# Glossary used here (AGENTS.md):
#   document = one whole item (one conversation, one session, one paper).
#   section  = a segment of a document.
#   clause   = what annotation produces from a section.
#   document_key identifies a document. source_path is the file it came from.
#
# Decisions applied (made by the user, not re-opened here):
#   - prune is a rake task. It deletes a document whose source file no longer
#     exists on disk, unless the document is archived. Its sections and clauses
#     are deleted with it.
#   - an archived document is never deleted by prune.
#   - archived documents are excluded from default context retrieval. The
#     opt-in that includes them is not designed in this stage.
#   - archive state is a nullable timestamp column, archived_at. A document is
#     archived when archived_at is not null. Archive sets it to now; unarchive
#     sets it to null. Neither changes updated_at. A migration is needed.
#     Archiving an archived document, or unarchiving an unarchived one, changes
#     nothing and prints a notice.
#   - rake arguments are used, not ENV. The dry run is the rake argument
#     "dry-run" on db:prune_missing_sources.
#
# Assumptions, each listed as a question in the report:
#   - Prune output is one line: "prune deleted=<n> kept_archived=<n> kept_unreadable=<n>".
#   - "Missing" means the path lookup raises Errno::ENOENT. Any other error means
#     "unreadable", and the document is kept.
#   - Archiving an already archived document keeps the original archived_at and
#     writes no new timestamp. The archive task prints a notice that the document
#     is already archived and exits 0. Unarchiving an unarchived document is the
#     same kind of no-op: a notice that it is not archived, exit 0.
#   - Rake task names db:prune_missing_sources, db:archive_document and
#     db:unarchive_document are kept.
#
# STRIDE gate (specifier): three trust-boundary crossings.
#   (a) filesystem lookup of a document's source_path    -> 3 misuse scenarios
#   (b) source_path column values (written by ingest from untrusted files) -> 1 misuse scenario
#   (c) rake argument naming a document to archive        -> 2 misuse scenarios

Feature: Prune deletes documents whose source file is gone, unless they are archived

  Background:
    Given a database with a collection "claude-chats"
    And a temporary directory holding "present.json" as a source file
    And document "doc-present" with source_path pointing at "present.json", which exists, archived_at null, with 2 sections and 2 clauses
    And document "doc-gone" with source_path pointing at "gone.json", which does not exist, archived_at null, with 2 sections and 2 clauses
    And document "doc-gone-archived" with source_path pointing at "gone-archived.json", which does not exist, archived_at set to a timestamp, with 1 section and 1 clause

  Scenario: A document whose source file is missing and which is not archived is deleted with its sections and clauses
    When I run "rake db:prune_missing_sources"
    Then the exit status is 0
    And document "doc-gone" no longer exists
    And no section row with document "doc-gone" exists
    And no clause row whose section belonged to "doc-gone" exists

  Scenario: A document whose source file exists is untouched
    Given the rows of "doc-present", its sections and its clauses are recorded
    When I run "rake db:prune_missing_sources"
    Then the rows of "doc-present", its sections and its clauses are identical to the recording

  Scenario: An archived document whose source file is missing is kept
    When I run "rake db:prune_missing_sources"
    Then document "doc-gone-archived" still exists with its section and clause
    And its archived_at is not null

  Scenario: The prune reports how many documents it deleted and how many it kept as archived
    When I run "rake db:prune_missing_sources"
    Then the last line of output is "prune deleted=1 kept_archived=1 kept_unreadable=0"

  Scenario: The dry run reports the same counts and changes nothing
    Given the database rows are recorded
    When I run "rake db:prune_missing_sources[dry-run]"
    Then the exit status is 0
    And the last line of output is "prune deleted=1 kept_archived=1 kept_unreadable=0"
    And the database rows are identical to the recording

  Scenario: Running prune twice is idempotent
    When I run "rake db:prune_missing_sources"
    And I run "rake db:prune_missing_sources" a second time
    Then the second run's last line of output is "prune deleted=0 kept_archived=1 kept_unreadable=0"
    And the database rows after the second run are identical to the rows after the first run

  Scenario: Archiving a document sets archived_at to the current time and changes nothing else
    Given the row of "doc-present" and its sections and clauses are recorded, including its updated_at value
    And the time before the run is recorded as T0
    When I run "rake db:archive_document[doc-present]"
    And the time after the run is recorded as T1
    Then the exit status is 0
    And the archived_at of "doc-present" is not null and is between T0 and T1
    And no other column of the "doc-present" row changed, including updated_at
    And no section or clause row changed

  Scenario: Archiving an already archived document is a no-op that prints a notice
    Given the archived_at of "doc-gone-archived" is recorded as A0
    And the row of "doc-gone-archived" and its sections and clauses are recorded, including its updated_at value
    When I run "rake db:archive_document[doc-gone-archived]"
    Then the exit status is 0
    And the output is a notice that "doc-gone-archived" is already archived
    And the archived_at of "doc-gone-archived" is A0, with the same value, and no new timestamp is written
    And the database rows are identical to the recording, including updated_at
    And no section or clause row changed

  Scenario: Unarchiving a document sets archived_at to null and changes nothing else
    Given "doc-gone-archived" is archived
    And the row of "doc-gone-archived" and its sections and clauses are recorded, including its updated_at value
    When I run "rake db:unarchive_document[doc-gone-archived]"
    Then the exit status is 0
    And the archived_at of "doc-gone-archived" is null
    And no other column of the "doc-gone-archived" row changed, including updated_at
    And no section or clause row changed

  Scenario: Unarchiving a document that is not archived is a no-op that prints a notice
    Given the row of "doc-present" and its sections and clauses are recorded, including its updated_at value
    When I run "rake db:unarchive_document[doc-present]"
    Then the exit status is 0
    And the output is a notice that "doc-present" is not archived
    And the database rows are identical to the recording, including updated_at

  Scenario: Unarchiving then running prune deletes the document once its source is still missing
    When I run "rake db:unarchive_document[doc-gone-archived]"
    And I run "rake db:prune_missing_sources"
    Then document "doc-gone-archived" no longer exists

  Scenario: Archiving an unknown document key exits non-zero and changes no row
    Given the database rows are recorded
    When I run "rake db:archive_document[no-such-document]"
    Then the exit status is non-zero
    And the output names the key "no-such-document" and says no document matched
    And the database rows are identical to the recording

  # STRIDE: Tampering and Elevation of privilege through the rake argument,
  # trust-boundary crossing (c). Misuse scenario 1 of 2. A wildcard or empty key
  # must match nothing. It must not archive every document.
  Scenario Outline: An archive key that is a wildcard or empty matches no document and changes no row
    Given the database rows are recorded
    When I run "rake db:archive_document[<key>]"
    Then the exit status is non-zero
    And no document row changed
    And the database rows are identical to the recording

    Examples:
      | key |
      | *   |
      | %   |
      |     |

  # STRIDE: Tampering through the rake argument, trust-boundary crossing (c).
  # Misuse scenario 2 of 2. A key that looks like an option must be a literal
  # key, not a flag.
  Scenario: An archive key that looks like an option is treated as a literal key and matches nothing
    Given the database rows are recorded
    When I run "rake db:archive_document[--all]"
    Then the exit status is non-zero
    And no document row changed

  # STRIDE: Denial of service and Tampering through the filesystem lookup,
  # trust-boundary crossing (a). Misuse scenario 1 of 3. A permission error
  # is not a missing file. The document is kept and a warning is logged.
  Scenario: A source path lookup that fails with permission denied keeps the document and warns
    Given the source path lookup of "doc-gone" raises Errno::EACCES
    When I run "rake db:prune_missing_sources"
    Then document "doc-gone" still exists with its sections and clauses
    And exactly one warning is logged with keyword fields component "PruneMissingSources", document_key "doc-gone", and reason "source_unreadable"
    And the warning contains no source path and no message text
    And the last line of output is "prune deleted=0 kept_archived=1 kept_unreadable=1"

  # STRIDE: Denial of service through the filesystem lookup, trust-boundary
  # crossing (a). Misuse scenario 2 of 3. An unreadable mount reports errors
  # other than ENOENT, and the document is kept.
  Scenario Outline: A source path on an unreadable mount keeps the document and warns
    Given the source path lookup of "doc-gone" raises <error>
    When I run "rake db:prune_missing_sources"
    Then document "doc-gone" still exists
    And exactly one warning is logged with reason "source_unreadable"

    Examples:
      | error           |
      | Errno::EIO      |
      | Errno::ESTALE   |
      | Errno::ENOTCONN |

  # STRIDE: Tampering through the filesystem, trust-boundary crossing (a).
  # Misuse scenario 3 of 3. Prune removes database rows only. It never writes
  # to, renames or deletes a file on disk, including a file a source_path points at.
  Scenario: Prune never writes to or deletes any file on disk
    Given a file "outside-the-collection.txt" in the temporary directory's parent, and document "doc-traversal" whose source_path is "../outside-the-collection.txt" which exists, archived_at null
    And the file's bytes and modification time are recorded
    When I run "rake db:prune_missing_sources"
    Then the file "outside-the-collection.txt" exists with the recorded bytes and modification time
    And no file in the temporary directory was created, renamed or removed by the prune

  # STRIDE: Tampering through the source_path column, trust-boundary crossing (b).
  # Misuse scenario 1 of 1. An empty or null source_path cannot be checked, so
  # the document is kept and a warning is logged, not deleted.
  Scenario Outline: A document with an empty or null source path is kept and warned, not deleted
    Given document "doc-no-path" with source_path <source_path>, archived_at null
    When I run "rake db:prune_missing_sources"
    Then document "doc-no-path" still exists with its sections and clauses
    And exactly one warning is logged with keyword fields component "PruneMissingSources", document_key "doc-no-path", and reason "source_path_missing"
    And the last line of output counts "doc-no-path" in kept_unreadable

    Examples:
      | source_path |
      | ""          |
      | null        |

  # Retrieval exclusion. The opt-in is not designed here. Only the default is
  # specified.
  Scenario: An archived document does not appear in default context retrieval
    Given "doc-gone-archived" has archived_at not null and a clause whose text matches the query "lighthouse"
    And "doc-present" has archived_at null and a clause whose text matches the query "lighthouse"
    When I run a default context retrieval for "lighthouse" with no archive opt-in
    Then no result has document_key "doc-gone-archived"
    And the result includes the clause of "doc-present"
