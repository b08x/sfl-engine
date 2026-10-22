# QA procedure — transcription and image-meta loaders

Manually runnable checks against the finished work, in order. Steps 1-8
apply to the loader change itself; steps 9-12 apply only once the
@registration scenarios (features/registration.feature) are approved and
implemented. Every step has an expected result a person or script can
check; a failing step blocks the next.

## A. Preflight (repo health)

1. Run `bundle exec rake`.
   Expected: RSpec, RuboCop and the Zeitwerk check all pass. In
   particular the Zeitwerk check fails before the change if the four
   draft files are still present in their broken shape (one contains a
   markdown fence, two define modules whose names do not match their
   paths) and passes after the drafts are replaced by
   `transcription_source.rb` and `image_meta_source.rb`.

2. Run `git status --short lib/sfl/core/loaders/`.
   Expected: the four draft files (`transcription_chat_source.rb`,
   `transcription_loader.rb`, `transcription_text_loader.rb`,
   `yaml_document_analysis_loader.rb`) are deleted, and exactly two new
   files exist: `transcription_source.rb` and `image_meta_source.rb`.

## B. Spec coverage (convention: every lib file has a matching spec)

3. Check that `spec/core/loaders/transcription_source_spec.rb` and
   `spec/core/loaders/image_meta_source_spec.rb` exist and follow the
   existing spec conventions: `require "spec_helper"`, the
   `file_ref(path)` helper from `spec/support/file_ref_helper.rb`
   (never a raw path), fixture files under
   `spec/fixtures/loaders/` (new subdirectories `transcriptions/` and
   `image_meta/`), and `Tempfile.create` for inline content the way
   `spec/core/loaders/subtitle_source_spec.rb` builds SRT bodies inline.

4. Run `bundle exec rspec spec/core/loaders/transcription_source_spec.rb`.
   Expected: all examples pass, and the examples cover every scenario in
   `features/transcription_source.feature`: one turn per non-blank line,
   blank lines skipped without warnings, contiguous
   `#{file_id}#turn-#{index}` ids, speaker "User" with `is_user: true`,
   `sent_at` from the ref's mtime, `document_key`/`source_path` from
   `path_hint`, literal-text handling of fence/markup-looking lines, and
   `Loaders::Error` for empty files, blank-only files and non-.txt refs.

5. Run `bundle exec rspec spec/core/loaders/image_meta_source_spec.rb`.
   Expected: all examples pass, covering every scenario in
   `features/image_meta_source.feature`: one unit per file with
   `section_id "#{file_id}#meta"`, text from `description`, `sent_at`
   from a parseable `timestamp` and nil plus one warning otherwise,
   `model_used`/`evaluation` into metadata, `Loaders::Error` for a
   missing/blank/non-string description, unparseable YAML, non-mapping
   roots, and YAML containing `!ruby/object` tags (the spec must assert
   the parser used is the safe one — e.g. by expecting the error raised
   by safe parsing, not by rescuing a `NoMethodError` from an
   instantiated object).

6. Run `bundle exec rspec spec/core/loaders/`.
   Expected: the full loader suite passes — the new loaders break no
   sibling loader, and `catalog_spec.rb` still passes before
   registration is approved (the new loaders join the catalog only in
   step 9).

## C. Loader behavior on real data (console check, no ingest needed)

7. Run the transcription loader against a real vault file:
   ```
   bundle exec ruby -e 'require "sfl"; ref = SFL::Core::Refs::FileRefBuilder.call(ARGV[0]); units = SFL::Core::Loaders::TranscriptionSource.new(ref).each_unit.to_a; puts units.size; p units.first' ~/Notebook/Daily/transcription_2025-04-25_19-45-27.txt
   ```
   Expected: the unit count equals the file's non-blank line count
   (check with `grep -cve "^[[:space:]]*$" <file>`); the printed first
   unit shows `section_id` ending in `#turn-0`, `speaker: "User"`,
   `is_user: true`, a `sent_at` matching the file's mtime, and text
   equal to the first non-blank line, stripped. Nothing is written to
   stderr.

8. Run the image-meta loader against a real sidecar file (any
   `image-*.meta.yaml` under `~/Notebook/Daily/assets/`, e.g. in
   `2025-11-02 Document Analysis & Images/`), the same way with
   `ImageMetaSource`.
   Expected: exactly one unit; `text` equals the file's `description`
   value; `sent_at` equals its parsed `timestamp`; metadata carries
   `model_used` and `evaluation` when present; `speaker` is nil.

## D. Registration (only after the @registration scenarios are approved)

9. Run `bundle exec rspec spec/ingest/deterministic_rules_spec.rb`.
   Expected: new examples pass asserting `classify` on a
   `transcription_*.txt` path returns
   `{format: "transcription", mode: "conversation", source_type:
   "transcription"}`, on an `image-*.meta.yaml` path returns
   `{format: "image_meta", mode: "knowledge_base", source_type:
   "vault_image_meta"}`, and that `notes.txt`, `config.yaml`,
   `note.meta.yaml` and `docker-compose.yml` all still return nil.

10. Run `bundle exec rspec spec/core/loaders/catalog_spec.rb`.
    Expected: the catalog registers `:transcription` and `:image_meta`
    as simple ref-plus-optional-kwarg factories resolving to
    `TranscriptionSource` / `ImageMetaSource`.

11. End-to-end ingest of a real transcription file:
    ```
    bundle exec exe/sfl-analyze ingest ~/Notebook/Daily/transcription_2025-04-25_19-45-27.txt --collection qa-transcription --store
    ```
    Expected: exit code 0; the file is reported ingested (not queued for
    review); progress lines show one turn per non-blank line; no
    `[WARN]` lines beyond any expected for that file; repeating the run
    with the same unchanged file skips it (skip-if-unchanged via
    content_identity).

12. Negative end-to-end check: run the ingest CLI on a directory
    containing an ordinary `notes.txt` file (with registration live).
    Expected: `notes.txt` is not classified as a transcription — it goes
    to the classifier and is queued for review or skipped as before,
    proving the narrow basename rule did not broaden .txt handling.

## E. Documentation

13. Run `grep -rn "Not registered" docs/ingest-review/`.
    Expected: no matches. Each of the four docs' Status sections names
    the final production class and file per
    `features/ingest_review_docs.feature`, records the resolved field
    mapping, and (for the three transcription docs) states the
    supersession by `TranscriptionSource`.

## F. Hygiene

14. Run `bundle exec rubocop lib/sfl/core/loaders/transcription_source.rb lib/sfl/core/loaders/image_meta_source.rb spec/core/loaders/transcription_source_spec.rb spec/core/loaders/image_meta_source_spec.rb`.
    Expected: no offenses, including `# frozen_string_literal: true` as
    the first line of each `.rb` file.

15. Confirm neither new file reads `ENV`, logs through anything other
    than `warn`-to-stderr per the SubtitleSource precedent, or reads
    config:
    `grep -nE "ENV|Logger" lib/sfl/core/loaders/transcription_source.rb lib/sfl/core/loaders/image_meta_source.rb`
    Expected: no matches.
