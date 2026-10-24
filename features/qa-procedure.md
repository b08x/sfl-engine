# QA procedure — loaders, sources and store features

Manually runnable checks against the finished work, in order. Steps 1-8
apply to the loader change itself; steps 9-12 apply only once the
@registration scenarios (features/registration.feature) are approved and
implemented. Every step has an expected result a person or script can
check; a failing step blocks the next.

## A. Preflight (repo health)

Steps 1-2 verify the cleanup after incident `4a53727` and describe the
pre-quarantine world: drafts used to be written straight into
`lib/sfl/core/loaders/`. Since the loader-draft quarantine they land in
`docs/ingest-review/candidates/` instead; section G pins that behavior.

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
    Expected: no matches in the four superseded docs. Each of the four
    docs' Status sections names the final production class and file per
    `features/ingest_review_docs.feature`, records the resolved field
    mapping, and (for the three transcription docs) states the
    supersession by `TranscriptionSource`.
    Matches in fresh candidate docs are expected, not a failure: the
    loader drafter's review-doc template writes `**Not registered.**`
    into every draft it produces (`lib/sfl/ingest/loader_drafter.rb`),
    because a draft is never registered automatically.

## F. Hygiene

14. Run `bundle exec rubocop lib/sfl/core/loaders/transcription_source.rb lib/sfl/core/loaders/image_meta_source.rb spec/core/loaders/transcription_source_spec.rb spec/core/loaders/image_meta_source_spec.rb`.
    Expected: no offenses, including `# frozen_string_literal: true` as
    the first line of each `.rb` file.

15. Confirm neither new file reads `ENV`, logs through anything other
    than `warn`-to-stderr per the SubtitleSource precedent, or reads
    config:
    `grep -nE "ENV|Logger" lib/sfl/core/loaders/transcription_source.rb lib/sfl/core/loaders/image_meta_source.rb`
    Expected: no matches.

## G. Loader-drafter quarantine and validation gates

Applies to SFL::Ingest::LoaderDrafter
(features/loader_draft_quarantine.feature,
features/loader_draft_validation.feature,
features/loader_draft_safety.feature): LLM candidate loader drafts
must never again land in the Zeitwerk-eager-loaded
lib/sfl/core/loaders/ tree, must pass syntax and naming gates before
anything is written, and must stay human-reviewable.

16. Confirm the drafter no longer names the loaded tree:
    `grep -n "lib/sfl/core/loaders" lib/sfl/ingest/loader_drafter.rb`
    Expected: no matches. The constructor takes `drafts_dir:`
    (default `docs/ingest-review/candidates`), `docs_dir:` (default
    `docs/ingest-review`) and an injectable `predictor:` seam, and no
    kwarg points inside `lib/`. `SFL::Boot` and `.env.example` are
    unchanged — the quarantine default needs no ENV knob.

17. Run `bundle exec rspec spec/ingest/loader_drafter_spec.rb`.
    Expected: the file exists (the AGENTS.md mirrored-spec rule for
    lib/sfl/ingest/loader_drafter.rb) and passes with an injected
    predictor double — no network, no LLM. Its examples cover the
    quarantine destination (never lib/sfl/core/loaders), the three
    gates (class-name pattern, RubyVM::AbstractSyntaxTree syntax
    parse, declared `class <class_name>` under SFL::Core::Loaders),
    the `<stem>-invalid.md` evidence doc with "INVALID — do not
    promote", the raised error hierarchy, the idempotent identical
    re-draft, the differing-draft DuplicateDraftError, and the
    `{loader_path:, doc_path:}` return pair.

18. Reproduce the incident shape, safely:
    ```
    mkdir -p docs/ingest-review/candidates
    printf '```ruby\nclass Broken\n' > docs/ingest-review/candidates/qa_broken_draft.rb
    bundle exec rake
    ```
    Expected: RSpec, RuboCop and the Zeitwerk check all pass — a
    syntactically broken .rb inside the quarantine cannot break the
    run. This only holds because `docs/ingest-review/candidates/` is
    listed under `AllCops: Exclude:` in `.rubocop.yml` (RuboCop's
    default includes inspect `docs/**/*.rb`; without the exclude this
    step fails with a Lint/Syntax offense). Delete the probe file
    afterwards.

19. End-to-end draft of a real unrecognized file:
    ```
    bundle exec exe/sfl-analyze ingest <a file the classifier returns "unknown" for> --collection qa-drafts
    ```
    Expected: exit code 0; the file is queued with status
    `loader_drafted`; a draft `.rb` exists under
    `docs/ingest-review/candidates/` and nothing new exists under
    `lib/sfl/core/loaders/`; `ruby -c` on the draft prints "Syntax
    OK"; its review doc's Status section says "Not registered", names
    the quarantine path, and gives the promotion recipe (`ruby -c`,
    copy to `lib/sfl/core/loaders/`, mirrored spec, entry in
    `SFL::Ingest::DeterministicRules`) — no automatic registration.

20. Re-run step 19 on the same file.
    Expected: either the same two paths come back with the existing
    draft unmodified (byte-identical re-draft), or the file is
    recorded `draft_failed` with a message naming the collision
    (differing re-draft). In both cases the first draft and its doc
    are untouched and `ls docs/ingest-review/candidates/` shows no
    suffixed junk files.

21. Attribution check for the step 19/20 runs: read the stderr log (or
    `journalctl SFL_RUN_ID=<id>`).
    Expected: every drafted and every failed file has its structured
    line — `ingest run complete` counts, and for each failure a
    `loader draft failed` line carrying `file:` and the gate named in
    the error message, all tagged with the run's `SFL_RUN_ID`.

22. Hygiene:
    `bundle exec rubocop lib/sfl/ingest/loader_drafter.rb spec/ingest/loader_drafter_spec.rb`
    and `grep -n "ENV" lib/sfl/ingest/loader_drafter.rb`.
    Expected: no RuboCop offenses (frozen_string_literal first line)
    and no ENV reads — configuration arrives as constructor
    arguments, with `SFL::Boot` injecting the `lm` as today.

## H. BERTopic sidecar, topic model and three analyses

Applies to the BERTopic sidecar command, SFL::Analysis::BertopicSidecar,
SFL::Analysis::TopicModeler, the three analyses, their rake eval tasks
and the analyses TUI tab (features/bertopic_sidecar.feature). Step 23
onward continues the numbering above. Steps 23-27 need no Ollama server
and no dataset. Steps 28-30 need a running Ollama server with
`embeddinggemma-2:440m` pulled. Steps 31-38 need the database and the
eval dataset.

23. Run `bundle exec rake`, then `bundle exec cucumber --dry-run features/bertopic_sidecar.feature`.
    Expected: RSpec, RuboCop and the Zeitwerk check all pass. The
    cucumber dry run parses the file with no syntax error; it reports
    the scenarios as undefined, because the repo ships no step
    definitions and none are to be added.

24. Run `grep -rn tomoto Gemfile Gemfile.lock lib spec`.
    Expected: no matches. `bundle exec ruby -e 'require "sfl/analysis/topic_modeler"'`
    loads with no error when `tomoto` is not installed.

25. Run `python3 -m py_compile sidecar/spacy_sidecar.py`.
    Expected: exit code 0 and no output.

26. Pipe one synthetic bertopic request into the sidecar, with fake
    vectors and no Ollama:
    ```
    { printf '%s\n' '{"id":"t1","type":"bertopic","texts":["alpha beta","alpha gamma","delta epsilon","delta zeta","alpha beta gamma","delta epsilon zeta"],"embeddings":[[0.1,0.9,0.0],[0.2,0.8,0.1],[0.9,0.1,0.0],[0.8,0.2,0.1],[0.15,0.85,0.05],[0.85,0.15,0.0]],"nr_topics":2,"min_topic_size":2,"seed":42}'; sleep 5; } | python3 sidecar/spacy_sidecar.py --model <model named in sidecar/README.md>
    ```
    Expected: the first line is `{"type": "ready", "model": "<name>"}`.
    The next line has `"id": "t1"`, `"topics"` as an array of 6
    integers, `"topic_words"` as an object whose values are arrays of
    strings, and `"outlier_topic": -1`. JSON object keys arrive as
    strings; the Ruby client converts them to integers. No network
    access is needed; disconnect the network and repeat to confirm.

27. Pipe a malformed line followed by a valid request into the same
    command:
    ```
    { printf '%s\n' '{"id":"x","type":"bertopic","texts":['; printf '%s\n' '<the valid request from step 26>'; sleep 5; } | python3 sidecar/spacy_sidecar.py --model <model>
    ```
    Expected: one error line with `"id": null` and an `"error"`
    message that does not repeat the malformed text. The valid request
    that follows is answered with `"id": "t1"`. The sidecar is still
    running.

28. Stop the Ollama server, then run
    `bundle exec rake eval:tenor_coherence`.
    Expected: non-zero exit. The message is a typed embedding error
    that names `ollama`, `embeddinggemma-2:440m` and the endpoint URL.
    No file under `output/eval/` is written by this run.

29. Start the Ollama server. Run `ollama list` and confirm
    `embeddinggemma-2:440m` appears. Then set
    `SFL_TASK_EMBEDDING_MODEL=<a model name that is not pulled>` and run
    `bundle exec rake eval:tenor_coherence`.
    Expected: non-zero exit. The message names `ollama`, the unpulled
    model name, the endpoint URL, and the instruction to run
    `ollama pull`. No embeddings are produced. Unset the variable
    afterwards.

30. Run `bundle exec rspec spec/analysis/bertopic_sidecar_spec.rb spec/analysis/topic_modeler_spec.rb spec/analysis/engine_spec.rb`.
    Expected: all examples pass with a fake process runner and an
    injected embedding double. No Python process is spawned and no
    Ollama request is made. The examples cover the coverage gate at
    exactly 30 percent, the single retry with reduced `nr_topics` and
    `min_topic_size`, and the coverage error naming both attempts with
    no `topic_models` row written.

31. Run `bundle exec rake db:migrate`, then query the table with
    `psql "$DATABASE_URL" -c '\d topic_models'`.
    Expected: the migration applies. The table has a document key, a
    JSONB `topics`, a JSONB `topic_words`, `coverage`, a run id, and
    `created_at` and `updated_at`. Record the row count, run a
    coverage-failing fit (the spec fixture in step 30 is the simplest
    source), and confirm the row count is unchanged.

32. Run `bundle exec rake eval:tenor_coherence`, `bundle exec rake eval:process_mix`
    and `bundle exec rake eval:gap_analysis`.
    Expected: each exits 0 when `output/eval/nd-11` loads. Each writes
    a markdown and a JSON report under `output/eval/`. Only
    `output/eval/nd-11` exists today, so conversations 12, 13 and 14 are
    listed as missing in each report and n counts only conversation 11.
    The report files name conversation 11 as used.

33. Open the tenor-coherence JSON report and compare its `n` with the
    count of sections that have both `avg_tenor` and
    `semantic_coherence_score` non-null in the loaded data, computed
    independently (for example with a short `jq` filter over
    `output/eval/nd-11/conversation_analysis.json`).
    Expected: the two counts are equal. The report's `n` is not
    asserted to be 29; 29 is the expected count only on a dataset
    where conversations 11 to 14 all load.

34. Open the process-mix report.
    Expected: one row per speaker with six process-type proportions
    (material, mental, relational, verbal, behavioral, existential)
    and one deviation value from the material baseline. A speaker
    with no llm or human clauses appears as "no data", not as a zero
    deviation. No row uses a source other than llm or human.

35. Open the gap-analysis report.
    Expected: the long-pause threshold per conversation is the larger of
    its 75th-percentile pause and the floor (600 seconds by default).
    The report names the test used (Fisher exact, or permutation when
    an expected cell count is below 5), gives its p-value and gives
    the group counts. Re-running the task with the same seed reports
    the same p-value.

36. Run `bundle exec rspec spec/tui/analyses_spec.rb spec/tui/consolidation_spec.rb`.
    Expected: all examples pass. The analyses tab renders into the
    ratatui test terminal, and the consolidation spec confirms no
    `ENV` read of the embedding variables outside `lib/sfl/boot*`.

37. Start the TUI with `bundle exec exe/sfl-tui`, press `5`, then
    press `q`.
    Expected: five tabs in the tab bar; the fifth is the analyses tab.
    It shows the coefficient, p-value and n from the newest
    tenor-coherence report. Move the file `output/eval/gap_analysis.md`
    aside and reopen the tab: the gap panel shows "not run yet" and
    names `eval:gap_analysis`. Restore the file afterwards.

38. STRIDE checks against the file boundaries:
    a. Create `output/eval/tenor_coherence.md` as a symlink to a
       throwaway file outside `output/eval/` (for example under the
       session scratchpad), run `bundle exec rake eval:tenor_coherence`.
       Expected: non-zero exit naming the report path; the symlink
       target is byte-identical afterwards. Remove the symlink.
    b. Run `bundle exec rake "eval:tenor_coherence[11,../../secrets]"`
       or set the equivalent `CONVERSATIONS` argument.
       Expected: non-zero exit naming `../../secrets`; no file outside
       `output/eval/nd-<n>/` is opened.
    c. Write `{not json` into `output/eval/tenor_coherence.md`, then
       open the analyses tab.
       Expected: the tenor panel shows "unreadable report"; the other
       panels and tabs still work. Restore the report by re-running
       the task.
    d. Confirm with `grep -rn "CONFIDENTIAL-PHRASE" output/eval/` after
       planting that phrase in a section of conversation 11 (a
       throwaway copy of the dataset, not the real file).
       Expected: no match in any report.

39. Logging check for steps 26-37: run one eval task with
    `SFL_LOG_TARGET=stderr` and read the stderr lines.
    Expected: each sidecar restart, if any, has a line carrying
    `component`, `attempt` and `exit_status` fields, and the line
    carries the run's `SFL_RUN_ID`. With `SFL_LOG_TARGET=stderr,journald`,
    `journalctl SFL_RUN_ID=<id>` returns the same lines.

40. Hygiene and full gate:
    `bundle exec rubocop` on each new file under `lib/sfl/analysis/`,
    `lib/sfl/tui/analyses.rb`, `rakelib/eval.rake` and their specs;
    then `bundle exec rake`, `bundle exec cucumber`, and
    `bundle exec bundler-audit check` (the Gemfile changed).
    Expected: no RuboCop offenses; `bundle exec rake` passes;
    `bundle exec cucumber` reports every scenario as undefined and
    none as failed, because the repo ships no step definitions (the
    verifier gate decides acceptance from the scenario text); bundler-audit
    reports no vulnerabilities.

## I. SillyTavern group-chat loader (console check, no ingest needed)

Acceptance scenarios: `features/sillytavern_source.feature`. The five
sample sessions are in `output/eval/_src/sim_chats/`. Units are the
records that yield text under the rule in
`features/sillytavern_source.feature`: a system record with a String mes
is skipped; any other record with extractable text yields a unit. The
expected unit counts are 270, 713, 174, 114 and 62. Step 1 counts the
non-system records (`is_system` not true); for these five files that
count equals the loader's unit count. Run these from the repo root.

1. Count the sample sessions and their non-system records without the loader:
   ```
   bundle exec ruby -rjson -e 'ARGV.each { |f| recs = File.foreach(f).map { |l| JSON.parse(l) }; puts "#{File.basename(f)} units=#{recs.count { |r| r["is_system"] != true }}" }' output/eval/_src/sim_chats/'Branch #210 - 2024-6-19@16h23m07s.jsonl' output/eval/_src/sim_chats/'Branch #393 - 2024-6-16@03h31m11s.jsonl' output/eval/_src/sim_chats/2024-6-15@18h35m15s.jsonl output/eval/_src/sim_chats/2024-6-15@20h21m29s.jsonl output/eval/_src/sim_chats/2024-6-19@11h34m27s.jsonl
   ```
   Expected, in argument order: `units=270`, `units=713`, `units=174`,
   `units=114`, `units=62`. Branch #393 and `2024-6-19@11h34m27s.jsonl`
   have no system record, so every record there is a unit. Every line
   of the five files parses as JSON on its own, so each physical line is
   one record. Step 3 covers a message with a line break.

2. Run the loader against the first sample session:
   ```
   bundle exec ruby -e 'require "sfl"; ref = SFL::Core::Refs::FileRefBuilder.call(ARGV[0]); units = SFL::Core::Loaders::SillyTavernSource.new(ref, file_id: "st-210").each_unit.to_a; puts units.size; p units.first; p units.last' 'output/eval/_src/sim_chats/Branch #210 - 2024-6-19@16h23m07s.jsonl'
   ```
   Expected: the first line prints `270`. The first unit has
   `section_id` `"st-210#turn-0"`, `speaker` equal to the `name` of the
   first turn record, `is_user` equal to that record's `is_user`,
   `document_key` and `source_path` equal to the path passed in, and
   `metadata` `{"file_id" => "st-210", "source_file" => "Branch #210 - 2024-6-19@16h23m07s.jsonl"}`.
   Its `sent_at` is a UTC Time equal to the first turn's `send_date`
   read as US Eastern time (EDT, UTC-4, in June) and converted to UTC
   (for example `June 19, 2024 2:22pm` is `18:22:00 UTC`).
   The last unit's `section_id` is `"st-210#turn-269"`. Nothing is
   written to stderr.

3. Check a message with a line break. Write a three-record file in a
   scratch directory (not under `output/`): a system header on line 1,
   and on line 2 a turn record whose `mes` is `First line\nsecond line`
   with the two characters `\` and `n` in the file (not a real line
   break). Run the loader on it:
   ```
   bundle exec ruby -e 'require "sfl"; require "tmpdir"; Dir.mktmpdir do |d| path = File.join(d, "line_break.jsonl"); File.write(path, %({"name":"Header","is_user":false,"is_system":true,"is_group":true,"mes":"x","send_date":"June 15, 2024 6:35pm"}\n{"name":"Hobbes","is_user":false,"is_system":false,"send_date":"June 15, 2024 6:35pm","mes":"First line\\nsecond line"}\n{"name":"Steve","is_user":false,"is_system":false,"send_date":"June 15, 2024 6:36pm","mes":"Next turn"}\n)); units = SFL::Core::Loaders::SillyTavernSource.new(SFL::Core::Refs::FileRefBuilder.call(path), file_id: "st-break").each_unit.to_a; puts units.size; p units.first.text end'
   ```
   Expected: `2`, then `"First line\nsecond line"` with the line break kept
   as one character. The output has two units, one per physical line,
   and the first unit's text contains a line break.

4. Check that the last line may lack a trailing line break. Write a file
   in a scratch directory with no line break after its last byte: a
   system header, then the turn record `"first"`, then the turn record
   `"last, no line break"` with no newline at the end. Run the loader on
   it, as in step 3:
   ```
   bundle exec ruby -e 'require "sfl"; require "tmpdir"; Dir.mktmpdir do |d| path = File.join(d, "no_eol.jsonl"); File.write(path, %({"name":"Header","is_user":false,"is_system":true,"is_group":true,"mes":"x","send_date":"June 15, 2024 6:35pm"}\n{"name":"Hobbes","is_user":false,"is_system":false,"send_date":"June 15, 2024 6:35pm","mes":"first"}\n{"name":"Steve","is_user":false,"is_system":false,"send_date":"June 15, 2024 6:36pm","mes":"last, no line break"})); units = SFL::Core::Loaders::SillyTavernSource.new(SFL::Core::Refs::FileRefBuilder.call(path), file_id: "st-eof").each_unit.to_a; puts units.size; p units.last.section_id; p units.last.text end'
   ```
   Expected: `2`, then `"st-eof#turn-1"`, then `"last, no line break"`.
   The last record is a unit, and the file is not truncated.

5. Check the error path with a line that is not valid JSON. Write a file
   whose second physical line is `{"name":"Steve","mes":"never closed`
   in a scratch directory, then run the loader on it, as in step 3.
   Expected: exactly one `SFL::Core::Loaders::Error` is raised, its
   message names the file's basename and line `2`, and no units are
   printed. The error is rescued by the ingest boundary and does not
   stop the run.

6. Check the timing across each sample session. Count consecutive
   units whose `sent_at` decreases:
   ```
   bundle exec ruby -e 'require "sfl"; ARGV.each { |p| units = SFL::Core::Loaders::SillyTavernSource.new(SFL::Core::Refs::FileRefBuilder.call(p), file_id: "st").each_unit.to_a; dec = units.each_cons(2).count { |a, b| b.sent_at < a.sent_at }; puts "#{File.basename(p)} units=#{units.size} sent_at_decreases=#{dec} span_s=#{(units.last.sent_at - units.first.sent_at).to_i}" }' output/eval/_src/sim_chats/*.jsonl
   ```
   Expected: `units` equals the counts from step 1, and `sent_at_decreases=0`
   for each file. A non-zero value is a finding for the specifier, not a
   loader error. Record it in the report.

7. Check that send_date is the time source, not the file mtime. Run
   `touch` on a copy of the first sample session in a scratch directory
   with a different mtime, then repeat step 2 on the copy.
   Expected: every `sent_at` is unchanged from step 2.

8. Check the unusable send_date rule. Write a three-record file in a
   scratch directory: a system header on line 1, a record with
   `"send_date":"yesterday"` on line 2, and a record with
   `"send_date":"June 15, 2024 6:36pm"` on line 3. Run it with stderr
   visible (the default log target is stderr):
   ```
   bundle exec ruby -e 'require "sfl"; require "tmpdir"; Dir.mktmpdir do |d| path = File.join(d, "bad_date.jsonl"); File.write(path, %({"name":"Header","is_user":false,"is_system":true,"is_group":true,"mes":"x"}\n{"name":"Steve","is_user":false,"is_system":false,"send_date":"yesterday","mes":"one"}\n{"name":"Mason","is_user":false,"is_system":false,"send_date":"June 15, 2024 6:36pm","mes":"two"}\n)); units = SFL::Core::Loaders::SillyTavernSource.new(SFL::Core::Refs::FileRefBuilder.call(path), file_id: "st-bad").each_unit.to_a; puts units.size; p units.map(&:sent_at) end' 2>&1
   ```
   Expected: no exception. The output is `2`, then `[nil, 2024-06-15 22:36:00 UTC]`.
   stderr has exactly one warning line that carries the fields
   `component` (`SillyTavernSource`), `file` (the basename `bad_date.jsonl`),
   `line` (`2`) and `reason` (`send_date_unparseable`). The text `yesterday`
   does not appear anywhere in the warning.

9. Check the Eastern offset at the two DST boundaries. Write a four-record
   file in a scratch directory, one turn per boundary time, and run:
   ```
   bundle exec ruby -e 'require "sfl"; require "tmpdir"; dates = ["March 10, 2024 1:59am", "March 10, 2024 3:00am", "November 3, 2024 12:59am", "November 3, 2024 2:00am"]; Dir.mktmpdir do |d| path = File.join(d, "dst.jsonl"); File.write(path, dates.each_with_index.map { |s, i| %({"name":"T#{i}","is_user":false,"is_system":false,"send_date":"#{s}","mes":"m"}) }.join("\n") + "\n"); units = SFL::Core::Loaders::SillyTavernSource.new(SFL::Core::Refs::FileRefBuilder.call(path), file_id: "st-dst").each_unit.to_a; units.each { |u| p u.sent_at } end'
   ```
   Expected, one line each: `2024-03-10 06:59:00 UTC` (EST), `2024-03-10 07:00:00 UTC`
   (EDT), `2024-11-03 04:59:00 UTC` (EDT), `2024-11-03 07:00:00 UTC` (EST).
   The boundary dates are 2024-03-10 and 2024-11-03.

10. Check a non-String `mes` that is an array. Write a scratch file with a
   system header and a turn whose `mes` is `["first part", "second part"]`.
   Run the loader. Expected: one unit whose text is `first part` and
   `second part` joined by one line break, with no warning.

11. Check a hash `mes`. Write a scratch file with a turn whose `mes` is
   `{"count": 2, "outer": {"inner": "nested text"}}`. Expected: one unit
   whose text is `nested text`. The key names do not appear in the text.

12. Check a `mes` with no text. Write a three-record scratch file whose
   middle record has `"mes": 42`, then run the loader. Expected: two units
   (lines 1 and 3), and one warning with `reason` `mes_no_text`,
   `position` `middle`, and the neighbour names and flags. The warning
   contains no message text.

13. Check a missing `mes`. Write a three-record scratch file whose
   middle record has `"mes": null`, then run the loader. Expected: two
   units, no exception, and one warning with `reason` `mes_missing`,
   `position` `middle`, and `previous_name` and `next_name` set to the
   neighbouring speakers. Repeat with the null on line 1: `position` is
   `first` and `previous_name` is `nil`.

14. Check a system record with a non-String `mes`. Write a scratch file
   whose first line is a system record with `"mes": ["Group", "created"]`
   and a `send_date`, followed by one turn. Expected: two units, the
   first with text `Group` and `created` joined by one line break. The
   system record with a String `mes` is still skipped without a warning.

Known gaps for the reviewer: (a) Wall-clock times from 2:00 to
2:59 on 2024-03-10 and from 1:00 to 1:59 on 2024-11-03 are not covered
by any step or scenario. (b) The five sample files contain messages with
an escaped line break (`\n` inside the JSON string), but no step compares
the unit text from those files with the file content; step 3 checks the
case with a scratch file only.

## J. Claude export loader (streaming, real export, console check)

Acceptance scenarios: `features/json_records_source.feature`. The loader
class is `SFL::Core::Loaders::JsonRecordsSource`, registered under the
catalog key `:claude_export`. The file is
`/home/b08x/WorkspaceV3/Datasets/ClaudeExports/2026-09-27/conversations-000/conversations.json`
(124 MB, one top-level JSON array). Baselines, measured on 2026-10-24: 1008
conversations and 12920 messages. They are baselines, not contracts. Steps 1
to 4 read the file with `jq --stream`, which never holds the whole file in
memory. Steps 5 to 8 need the loader, which exists only after the Implementer
has built it. Run from the repo root. Set
`EXPORT=/home/b08x/WorkspaceV3/Datasets/ClaudeExports/2026-09-27/conversations-000/conversations.json`
first.

1. Confirm the file and its size:
   ```
   ls -l "$EXPORT"
   ```
   Expected: one regular file of about 124 MB (about 124,000,000 bytes).

2. Count the conversations with a streaming reader:
   ```
   jq --stream -c 'select(length==2 and (.[0]|length)==2 and .[0][1]=="uuid")' "$EXPORT" | wc -l
   ```
   Expected: `1008`.

3. Count the messages with the same reader:
   ```
   jq --stream -c 'select(length==2 and (.[0]|length)==4 and .[0][1]=="chat_messages" and .[0][3]=="uuid")' "$EXPORT" | wc -l
   ```
   Expected: `12920` messages in total. Of these, 11975 become sections and
   945 are skipped as empty (`text_empty`), with a warning, in step 5. Section
   numbers count only the yielded messages, so a skipped message leaves no gap.

4. Check the document keys in the file. Expected each line of output to match.
   ```
   jq --stream -r -c 'select(length==2 and (.[0]|length)==2 and .[0][1]=="uuid") | .[1]' "$EXPORT" | sort | uniq -d | wc -l
   jq --stream -c 'select(length==2 and (.[0]|length)==2 and .[0][1]=="chat_messages" and .[1]==[])' "$EXPORT" | wc -l
   jq --stream -r -c 'select(length==2 and .[0]==[0,"uuid"]) | .[1]' "$EXPORT" | head -1
   ```
   Expected:
   - the first command prints `0` (no uuid appears twice in the real export);
   - the second prints the number of zero-message conversations, call it `Z`;
   - the third prints the first conversation's uuid, call it `U`. It is the
     `document_key` and the prefix of the first section id.

5. Run the loader and count units, warnings and the first unit:
   ```
   bundle exec ruby -e 'require "sfl"; ref = SFL::Core::Refs::FileRefBuilder.call(ARGV[0]); units = SFL::Core::Loaders::JsonRecordsSource.new(ref).each_unit.to_a; puts units.size; puts units.first.section_id; puts units.first.document_key; puts units.map(&:document_key).uniq.size; puts units.count { |u| u.section_id !~ /\A[^#\n]+#turn-\d+\z/ }; puts units.group_by(&:document_key).all? { |_, us| us.each_with_index.all? { |u, i| u.section_id.end_with?("#turn-#{i}") } }' "$EXPORT" 2>warnings.err
   ```
   Expected, one value per output line:
   - line 1, units: `11975`. The run summary of the CLI command
     `sfl-analyze json-records "$EXPORT"` on a scratch copy reports
     `processed 11975, skipped text_empty 945, failed 0`. Each skipped message
     gives one warning. Every warning line names `JsonRecordsSource` and the
     basename `conversations.json`, and contains no message text and no uuid;
   - line 2, first section id: `U#turn-0` from step 4;
   - line 3, first document key: `U`;
   - line 4, distinct document keys: at most `1008 - Z`. The difference is
     the number of conversations whose messages all have empty text, which
     yield no units;
   - line 5, malformed section ids: `0`;
   - line 6, numbering gap check: `true`. In every document the section
     numbers run `0` to `n-1` with no gap.
   Also expected in `warnings.err`: zero lines with the reasons
   `no_document_key`, `no_section_list`, `not_a_record`, `no_known_shape`,
   `not_an_array`, `duplicate_document_key`, `invalid_document_key`,
   `parse_error` and `truncated`. Check with
   `grep -c 'no_document_key\|no_section_list\|not_a_record\|no_known_shape\|not_an_array\|duplicate_document_key\|invalid_document_key\|parse_error\|truncated' warnings.err`, which prints `0`.

6. Truncated file (an example only; the cut at 60,000,000 bytes is one
   truncation point, not the real export). Write a copy cut at 60,000,000
   bytes into the scratch directory, never over `$EXPORT`, and run a
   single-file load on the copy:
   ```
   export SCRATCH=<your scratch directory, as an absolute path>
   mkdir -p "$SCRATCH/json_records_qa"
   head -c 60000000 "$EXPORT" > "$SCRATCH/json_records_qa/conversations.json"
   bundle exec ruby -e 'require "sfl"; ref = SFL::Core::Refs::FileRefBuilder.call(ARGV[0]); units = SFL::Core::Loaders::JsonRecordsSource.new(ref).each_unit.to_a; puts units.size' "$SCRATCH/json_records_qa/conversations.json" >truncated.out 2>truncated.err; echo "exit=$?"
   cat truncated.out
   grep 'JsonRecordsSource' truncated.err
   ```
   Expected: `exit=1` (the loader raises `SFL::Core::Loaders::Error`, which
   is not rescued in this command); `truncated.out` is empty, so no unit
   count is printed; `truncated.err` contains `SFL::Core::Loaders::Error`,
   the file name `conversations.json`, the reason `truncated`, and the
   `byte_offset` `60000000` (the file size). No unit from the cut file is
   ingested: the all-or-nothing rule rolls back every unit of the file,
   including the complete conversations before the cut.
   The batch behavior (the failed file listed in the run summary, the
   redundancy skip) is covered by the feature scenarios and by the batch
   entry point, the `sfl-analyze json-records` command named in step 5.

7. Check that the run did not load the file whole. Run step 5 again under
   `/usr/bin/time -v` and read `Maximum resident set size`. Expected: under
   200 MB for a 124 MB file. A value near or above 124 MB means the file was
   read whole.

8. Check the duplicate-key warning count against step 4. The real export has
   no duplicate uuid, so the `duplicate_document_key` count is `0`, the same
   as step 4's first command. A nonzero count in either place is a finding.

Known gaps for the reviewer: (a) step 5's expected values depend on the
loader being built; (b) no step checks the 5 MiB oversized message on the
real file, which the feature scenario and a generated fixture cover; (c) the
streaming memory check in step 7 uses the real file, which is slow; (d) the
zero-message rule (no units, no document row) is a specifier assumption,
listed in the report.

## K. Prune of missing sources, archive timestamp and retrieval exclusion

Acceptance scenarios: `features/prune_missing_sources.feature`. Run prune
only against a test database. Never run the prune rake task against the
real `DATABASE_URL` before the dry run in step 5 has been read and the
document list has been checked. The tasks named here (`db:prune_missing_sources`,
`db:archive_document`, `db:unarchive_document`) and the `archived_at` column
(nullable timestamp, replacing the earlier boolean `archived`) do not exist
until the Implementer builds them. Write the output of each step to a scratch
file under the scratchpad, not under `output/`.

1. Create a test database from a copy of the real one. `DATABASE_URL` is the
   real database URL from `.env`, and `TEST_URL` is the same URL with the
   database name `sfl_prune_qa`:
   ```
   createdb sfl_prune_qa
   pg_dump -Fc "$DATABASE_URL" | pg_restore --no-owner -d sfl_prune_qa
   export DATABASE_URL="$TEST_URL"
   ```
   Expected: `pg_restore` exits 0 and this shell now points at `sfl_prune_qa`.
   Check with `psql "$DATABASE_URL" -c "select count(*) from documents"`.
   The count equals the real count. Do not continue if it does not.

2. Set up three documents in the test database. Make a scratch directory,
   create one real file in it, and point three documents at paths:
   ```
   export SCRATCH=<your scratch directory, as an absolute path>
   mkdir -p "$SCRATCH/prune_qa"
   echo '{}' > "$SCRATCH/prune_qa/present.json"
   psql "$DATABASE_URL" -c "update documents set source_path = '$SCRATCH/prune_qa/present.json' where document_key = '<KEY_PRESENT>'"
   psql "$DATABASE_URL" -c "update documents set source_path = '/nonexistent/prune_qa/gone.json' where document_key = '<KEY_GONE>'"
   psql "$DATABASE_URL" -c "update documents set source_path = '/nonexistent/prune_qa/gone-archived.json' where document_key = '<KEY_ARCHIVED>'"
   psql "$DATABASE_URL" -c "update documents set archived_at = null where document_key in ('<KEY_PRESENT>','<KEY_GONE>','<KEY_ARCHIVED>')"
   ```
   Replace `<KEY_PRESENT>`, `<KEY_GONE>` and `<KEY_ARCHIVED>` with three
   `document_key` values from `select document_key, section_count from documents limit 10`.
   Expected: the three `update` statements that set `source_path` each report
   `UPDATE 1`. The `archived_at` update reports `UPDATE 3`, which clears the
   archive state of all three keys, so step 3 archives the third document
   for the first time. `<scratch>` below means the same `$SCRATCH` directory.
   Record the state for later comparison:
   ```
   psql "$DATABASE_URL" -At -c "select count(*) from documents; select count(*) from sections; select count(*) from clauses" > before.txt
   psql "$DATABASE_URL" -At -c "select document_key, updated_at from documents where document_key = '<KEY_ARCHIVED>'" > archived_before.txt
   ```

3. Archive the third document with the archive task (documented in the
   task's `--help` or in the rake file header):
   ```
   date -u +%Y-%m-%dT%H:%M:%S
   bundle exec rake "db:archive_document[<KEY_ARCHIVED>]"; echo "exit=$?"
   date -u +%Y-%m-%dT%H:%M:%S
   psql "$DATABASE_URL" -At -c "select archived_at is not null from documents where document_key = '<KEY_ARCHIVED>'"
   psql "$DATABASE_URL" -At -c "select document_key, updated_at from documents where document_key = '<KEY_ARCHIVED>'" | diff - archived_before.txt && echo "updated_at unchanged"
   psql "$DATABASE_URL" -At -c "select archived_at, updated_at from documents where document_key = '<KEY_ARCHIVED>'" > archived_after_archive.txt
   ```
   Expected: `exit=0`. The `archived_at is not null` query prints `t`. The
   `archived_at` value lies between the two `date` outputs. The `updated_at`
   line is unchanged, so `diff` prints nothing and `updated_at unchanged`
   prints. Only that one row's `archived_at` changed.

4. Confirm the task rejects a wildcard key, and that archiving an archived
   document is a no-op:
   ```
   bundle exec rake "db:archive_document[*]"; echo "exit=$?"
   psql "$DATABASE_URL" -At -c "select count(*) from documents where archived_at is not null"
   bundle exec rake "db:archive_document[<KEY_ARCHIVED>]"; echo "exit=$?"
   psql "$DATABASE_URL" -At -c "select archived_at, updated_at from documents where document_key = '<KEY_ARCHIVED>'" | diff - archived_after_archive.txt && echo "unchanged"
   ```
   Expected: the wildcard `exit=` is non-zero, and the count is `1` (step 3's
   document only). The re-archive `exit=` is `0`, and its output includes a
   notice that `<KEY_ARCHIVED>` is already archived. The `diff` prints nothing
   and `unchanged` prints: `archived_at` keeps the step 3 value and no new
   timestamp is written.

5. Dry run. Read the output before any real run:
   ```
   bundle exec rake "db:prune_missing_sources[dry-run]"; echo "exit=$?"
   psql "$DATABASE_URL" -At -c "select count(*) from documents; select count(*) from sections; select count(*) from clauses" | diff - before.txt && echo "unchanged"
   ```
   Expected: exit 0; the last output line is
   `prune deleted=1 kept_archived=1 kept_unreadable=0`; the `diff` prints
   nothing and `unchanged` prints. The dry run names the document that
   would be deleted, which is `<KEY_GONE>`. Stop here if it names any other
   document.

6. Real prune against the test database:
   ```
   bundle exec rake db:prune_missing_sources; echo "exit=$?"
   ```
   Expected: exit 0; last line `prune deleted=1 kept_archived=1 kept_unreadable=0`.
   Then `psql "$DATABASE_URL" -At -c "select document_key from documents where document_key in ('<KEY_PRESENT>','<KEY_GONE>','<KEY_ARCHIVED>') order by 1"`
   lists `<KEY_ARCHIVED>` and `<KEY_PRESENT>` only. The sections and clauses
   of `<KEY_GONE>` are gone: the count of rows in `sections` falls by
   `<KEY_GONE>`'s section count from step 2, and the `clauses` count falls
   by the number of clauses that belonged to `<KEY_GONE>`'s sections (record
   that number before step 6 with a join on `clauses.section_id`).
   The file `present.json` still exists: `test -f <scratch>/prune_qa/present.json; echo $?` is `0`.

7. Idempotence. Run the prune again:
   ```
   bundle exec rake db:prune_missing_sources; echo "exit=$?"
   ```
   Expected: exit 0; last line `prune deleted=0 kept_archived=1 kept_unreadable=0`.

8. Unarchive, then prune. First, unarchiving an unarchived document is a
   no-op. `<KEY_PRESENT>` is not archived:
   ```
   bundle exec rake "db:unarchive_document[<KEY_PRESENT>]"; echo "exit=$?"
   psql "$DATABASE_URL" -At -c "select archived_at is null from documents where document_key = '<KEY_PRESENT>'"
   ```
   Expected: `exit=0`; the output includes a notice that `<KEY_PRESENT>` is not
   archived; the query prints `t`.

   The unarchived document has a missing source and is deleted:
   ```
   bundle exec rake "db:unarchive_document[<KEY_ARCHIVED>]"; echo "exit=$?"
   psql "$DATABASE_URL" -At -c "select archived_at is null from documents where document_key = '<KEY_ARCHIVED>'"
   bundle exec rake db:prune_missing_sources
   psql "$DATABASE_URL" -At -c "select count(*) from documents where document_key = '<KEY_ARCHIVED>'"
   ```
   Expected: unarchive exits 0; the `archived_at is null` query prints `t`;
   the prune last line is `prune deleted=1 kept_archived=0 kept_unreadable=0`;
   the count is `0`.

9. Permission-denied path (the STRIDE case). Make a source file unreadable
   by its parent: set `<KEY_PRESENT>`'s source path under a directory with mode
   000, then prune. Run as a non-root user; root bypasses permissions.
   ```
   chmod 000 <scratch>/prune_qa
   psql "$DATABASE_URL" -c "update documents set source_path = '<scratch>/prune_qa/present.json' where document_key = '<KEY_PRESENT>'"
   bundle exec rake db:prune_missing_sources
   chmod 755 <scratch>/prune_qa
   ```
   Expected: the document `<KEY_PRESENT>` still exists; the output has one
   warning naming the document key, with reason `source_unreadable`, and
   no source path; the last line counts `kept_unreadable=1`.

10. Retrieval exclusion. Run a default context retrieval against the test
    database for a term that matches the archived document's clauses. The
    retrieval entry point is the one the Implementer exposes in the console
    (`SFL::Store::PgHybridRetriever#retrieve`). Expected: no result has
    `<KEY_ARCHIVED>` as its document key. Run this step once while
    `<KEY_ARCHIVED>` has `archived_at` set (after step 3) and confirm the
    exclusion holds then.

11. Clean up. Drop the test database and restore the environment:
    ```
    unset DATABASE_URL
    dropdb sfl_prune_qa
    rm -rf <scratch>/prune_qa
    ```
    Expected: `dropdb` exits 0.

Known gaps for the reviewer: (a) step 9 needs a non-root user; (b) step 10
depends on the retriever's embedder, and a fake embedder may be needed;
(c) the `--help` text of the archive task is not yet specified; (d) the
timestamp window in step 3 depends on the database and shell clocks agreeing.
