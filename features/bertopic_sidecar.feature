# BERTopic sidecar topic model and its three analyses.
#
# Source of truth: goals/bertopic-sidecar/facts.md and plan.md.
#
# Wire contract (pinned by the orchestrator):
#   request  {id, type:"bertopic", texts:[String], embeddings:[[Float]],
#             nr_topics:Integer|null, min_topic_size:Integer, seed:Integer}
#   response {id, topics:[Integer], topic_words:{Integer=>[String]},
#             outlier_topic:-1}
#   error    {id|null, error:String}   (existing protocol, unchanged)
#   client   fit(texts:, embeddings:, k: nil, seed:)
#              => {topics:, topic_words:, coverage:}
#
# Terms: a document is one whole item (one transcript file or one
# conversation). A section is a segment of a document, here one speaker
# turn, identified by section_id. A clause is what annotation produces
# from a section. Topic-model coverage is the share of sections with a
# topic other than -1.
#
# STRIDE: scenarios tagged @stride are misuse cases, one group per trust
# boundary crossing:
#   @crossing-a  Ruby <-> sidecar line-delimited JSON (stdin/stdout)
#   @crossing-b  Ruby -> Ollama embedding HTTP
#   @crossing-c  TopicModeler -> topic_models table
#   @crossing-d  rake eval tasks -> output/eval/ report files
#   @crossing-e  TUI analyses tab <- reports on disk
#
# Tags:
#   @journald — needs a reachable /run/systemd/journal/socket.
#   @fixture  — uses hand-computed values; the expected numbers are
#               stated in the scenario.
@bertopic
Feature: BERTopic sidecar topic model and its three analyses

  Background:
    Given the sfl-engine checkout with the BERTopic sidecar change applied
    And the sidecar is started from sidecar/spacy_sidecar.py with a model argument
    And SFL::Boot is the only code that reads the embedding environment variables

  # ---------------------------------------------------------------------
  # Sidecar protocol (facts 2, 4; plan step 1)
  # ---------------------------------------------------------------------

  Scenario: The sidecar keeps its startup handshake and answers a bertopic request on the same channel
    When the sidecar starts
    Then its first stdout line is {"type": "ready", "model": "<name>"}
    And it reads no request before writing that line
    When a bertopic request with id "req-1", 4 texts, 4 embedding vectors of 3 floats, nr_topics 2, min_topic_size 2 and seed 42 is written to stdin
    Then exactly one response line follows with id "req-1"
    And the response has "topics" as an array of 4 integers
    And the response has "topic_words" as an object whose values are arrays of strings
    And the response has "outlier_topic" equal to -1
    And the sidecar has started no second process

  Scenario: The bertopic engine computes from the vectors it is sent and makes no network call
    Given outbound network access from the sidecar process is blocked
    When a bertopic request with 6 texts and their vectors is answered
    Then the response is written with the standard shape
    And the sidecar loads no embedding model from disk or from the network

  Scenario: A null nr_topics is accepted and means automatic topic count
    When a bertopic request has "nr_topics": null
    Then the sidecar answers it with the standard response shape
    And it does not return an error for the null value

  Scenario: A bertopic request with a missing field gets the existing error shape and the sidecar keeps serving
    When a bertopic request with id "req-2" omits "min_topic_size"
    Then one error line is written with id "req-2" and an "error" message
    When a valid bertopic request with id "req-3" is written
    Then the response with id "req-3" is written

  # ---------------------------------------------------------------------
  # Embedding configuration (fact 3; plan step 2)
  # ---------------------------------------------------------------------

  Scenario: The embedding provider and model resolve from the task environment
    Given SFL_TASK_EMBEDDING_PROVIDER is "ollama"
    And SFL_TASK_EMBEDDING_MODEL is "embeddinggemma-2:440m"
    When SFL::Boot resolves the embedding configuration
    Then the provider is "ollama"
    And the model is "embeddinggemma-2:440m"

  Scenario: The documented defaults apply when both task variables are unset
    Given SFL_TASK_EMBEDDING_PROVIDER and SFL_TASK_EMBEDDING_MODEL are unset
    When SFL::Boot resolves the embedding configuration
    Then the provider is "ollama"
    And the model is "embeddinggemma-2:440m"

  Scenario: The embedding variables are read at call time, not cached when the library loads
    Given SFL::Boot is loaded while SFL_TASK_EMBEDDING_MODEL is unset
    When SFL_TASK_EMBEDDING_MODEL is set to "embeddinggemma-2:440m" and the configuration is resolved
    Then the resolved model is "embeddinggemma-2:440m"

  Scenario: No code outside SFL::Boot reads the embedding variables
    When the consolidation spec is run
    Then it passes
    And no ENV read of SFL_TASK_EMBEDDING_PROVIDER or SFL_TASK_EMBEDDING_MODEL exists under lib/, exe/ or rakelib/ outside lib/sfl/boot*

  Scenario: Both embedding variables are documented in .env.example
    Then .env.example names SFL_TASK_EMBEDDING_PROVIDER and SFL_TASK_EMBEDDING_MODEL, active or commented

  # ---------------------------------------------------------------------
  # Public API and k mapping (fact 1; plan step 4)
  # ---------------------------------------------------------------------

  Scenario: TopicModeler keeps the public methods the engine calls
    Then SFL::Analysis::TopicModeler responds to fit, turn_distributions, detect_topic_shifts, calculate_coherence and conversation_baseline
    And the engine calls those methods with the same arguments as before the change

  Scenario: A nil k maps to automatic topic count and an integer k maps to nr_topics
    When TopicModeler is built with k nil and fit is called
    Then the bertopic request carries "nr_topics": null
    When TopicModeler is built with k 5 and fit is called
    Then the bertopic request carries "nr_topics": 5

  Scenario: The tomoto gem and its LDA and HDP paths are gone
    Then Gemfile and Gemfile.lock name no tomoto gem
    And the TopicModeler spec passes with tomoto not installed

  Scenario: The file-based save and load_model methods are gone
    Then calling save on a TopicModeler raises NoMethodError
    And calling load_model on a TopicModeler raises NoMethodError

  # ---------------------------------------------------------------------
  # Topic input cleaning (fact 5; plan step 4)
  # ---------------------------------------------------------------------

  Scenario: Speaker names are removed from section text on the topic path
    Given a section by speaker "Alice" whose text is "Alice: we should ship the parser on Friday"
    When the topic input cleaner runs on the section
    Then the topic input for that section is "we should ship the parser on Friday"

  Scenario: System preambles, tool-call traces and repeated headers are removed from the topic path
    Given a section containing a system preamble "You are a helpful assistant.", a tool trace "<tool_call name=\"search\">", and a repeated header "## Transcript"
    When the topic input cleaner runs on the section
    Then none of the three boilerplate fragments appears in the topic input
    And the content words of the section remain in the topic input

  Scenario: Cleaning leaves Pass 1 output, sections and clauses byte-faithful
    Given a document whose sections include speaker names and boilerplate
    When Pass 1 runs and a topic model run is then performed on the document
    Then each stored section text equals the source section text byte for byte
    And the clause rows and Pass 1 output are identical to a run without the topic model run

  Scenario: Cleaning keeps one entry per section, in order, so topic results map back by position
    Given 5 sections of which 2 become empty after cleaning
    When the topic input cleaner runs
    Then it returns 5 entries in the input order, each carrying its section_id
    And the 2 emptied sections are kept as empty strings and are not dropped

  # ---------------------------------------------------------------------
  # Coverage gate and retry (fact 6; plan step 4)
  # ---------------------------------------------------------------------

  Scenario: A fit with coverage above 30 percent passes on the first attempt
    Given 10 sections of which the sidecar assigns a non-outlier topic to 4
    When TopicModeler fits the document
    Then exactly one bertopic request is sent
    And the result reports coverage 0.4
    And the result is stored once

  Scenario: Coverage of exactly 30 percent does not pass the gate
    Given 10 sections of which the sidecar assigns a non-outlier topic to 3
    When TopicModeler fits the document
    Then a second bertopic request is sent

  Scenario: A first attempt below the gate retries once with a smaller nr_topics and min_topic_size
    Given the first attempt used nr_topics 8 and min_topic_size 10 and reached coverage 0.2
    When the retry is sent
    Then the retry's nr_topics is less than 8
    And the retry's min_topic_size is less than 10
    And the retry reached coverage 0.5
    And the result reports coverage 0.5 and is stored once
    And exactly two bertopic requests were sent

  Scenario: When the first attempt used automatic topic count the retry sends null nr_topics and a smaller min_topic_size
    Given the first attempt used nr_topics null and min_topic_size 10 and reached coverage 0.1
    When the retry is sent
    Then the retry's nr_topics is null
    And the retry's min_topic_size is less than 10

  Scenario: Two attempts below the gate raise a coverage error that names both attempts and stores nothing
    Given the first attempt used nr_topics 8 and min_topic_size 10 and reached coverage 0.12
    And the retry used nr_topics 4 and min_topic_size 5 and reached coverage 0.18
    When TopicModeler fits the document
    Then a coverage error under SFL::Analysis::Error is raised
    And its message names attempt 1 with nr_topics 8, min_topic_size 10 and coverage 0.12
    And its message names attempt 2 with nr_topics 4, min_topic_size 5 and coverage 0.18
    And no topic_models row is written for the run
    And no further bertopic request is sent after the retry

  # ---------------------------------------------------------------------
  # Persistence (plan step 4 decision: topic_models table)
  # ---------------------------------------------------------------------

  Scenario: A successful fit is stored once with its fields
    Given a fit that passes the coverage gate for document key "transcript-42"
    When the fit is stored
    Then one topic_models row exists with document key "transcript-42"
    And the row holds topics and topic_words as JSONB
    And the row holds coverage, run id, created_at and updated_at

  Scenario: A stored fit reads back equal to the fit that was stored
    Given a stored fit with topics, topic_words and coverage
    When the fit is read back through the store layer
    Then the topics, topic_words and coverage equal the stored values

  # ---------------------------------------------------------------------
  # Embedding probe (fact 3 and plan risks)
  # ---------------------------------------------------------------------

  Scenario: The embedding probe passes when the configured model is pulled
    Given the Ollama server lists "embeddinggemma-2:440m"
    When the embedding probe runs before a topic fit
    Then the probe passes
    And the topic fit proceeds

  # ---------------------------------------------------------------------
  # Process mix (fact 7; plan step 5)
  # ---------------------------------------------------------------------

  Scenario: Each speaker's process-type distribution is compared with the material baseline
    Given a conversation with speakers "A" and "B" whose clauses span the six process types
    When the process-mix analysis runs
    Then the report gives, for each speaker, the six process-type proportions
    And the report gives, for each speaker, a deviation from the conversation's material baseline

  Scenario: A speaker whose distribution equals the baseline has zero deviation
    Given a speaker whose six proportions equal the material baseline
    When the process-mix analysis runs
    Then that speaker's deviation is 0

  Scenario: Clauses from sources other than llm or human do not contribute
    Given clauses from speaker "A" of which some have source "heuristic" and the rest have source "llm"
    When the process-mix analysis runs
    Then only the llm clauses are counted for speaker "A"

  Scenario: A speaker with no trusted clauses is reported as no data rather than as zero deviation
    Given speaker "C" whose only clauses have source "heuristic"
    When the process-mix analysis runs
    Then speaker "C" is reported as having no data
    And speaker "C" has no deviation value

  # ---------------------------------------------------------------------
  # Pause-vs-tenor-spike gap analysis (fact 8; plan step 5)
  # ---------------------------------------------------------------------

  Scenario: A pause is the gap between consecutive section timestamps within one conversation
    Given sections at 00:00, 00:03 and 00:09 in one conversation
    When the gap analysis computes pauses
    Then the pauses are 180 seconds and 360 seconds
    And no pause is computed across two conversations

  Scenario: The long-pause threshold is the 75th percentile of that conversation's own pauses
    Given a conversation whose pauses are 60, 120, 180, 240 and 300 seconds
    And a floor of 0 seconds
    When the gap analysis sets its long-pause threshold for that conversation
    Then the threshold is 240 seconds

  Scenario: The 10-minute floor overrides the percentile when it is higher
    Given a conversation whose pauses are 60, 120, 180, 240 and 300 seconds
    And the default floor of 600 seconds
    When the gap analysis sets its long-pause threshold for that conversation
    Then the threshold is 600 seconds
    And the 300-second pause is not a long pause

  Scenario: A configured floor replaces the default 10-minute floor
    Given a conversation whose pauses are 60, 120, 180, 240 and 300 seconds
    And a configured floor of 300 seconds
    When the gap analysis sets its long-pause threshold for that conversation
    Then the threshold is 300 seconds
    And a pause of 301 seconds is a long pause

  Scenario: Tenor spikes are the turns flagged by TenorTracker detect_significant_shifts
    Given TenorTracker#detect_significant_shifts flags sections 3 and 7 in a conversation
    When the gap analysis collects tenor spikes
    Then the spikes are sections 3 and 7

  @fixture
  Scenario: The spike rate after long pauses is tested with Fisher exact on a known table
    Given 4 sections follow a long pause, of which 3 are tenor spikes
    And 4 sections follow no long pause, of which 1 is a tenor spike
    When the gap analysis runs its test
    Then the test is Fisher exact
    And the two-sided p-value is 0.4857 to four decimal places
    And the report gives both group counts

  Scenario: A table with an expected cell count below 5 uses the permutation fallback and says so
    Given a 2x2 table of spike and non-spike counts after long pauses and after other pauses in which an expected cell count is below 5
    When the gap analysis runs its test with seed 7
    Then the report names the permutation test as the test used
    And a repeated run with seed 7 reports the same p-value

  # ---------------------------------------------------------------------
  # Tenor-vs-coherence Spearman (fact 6; plan step 5)
  # ---------------------------------------------------------------------

  @fixture
  Scenario: A perfectly monotone set of pairs gives a Spearman coefficient of 1.0
    Given 5 pairs (1,2), (2,4), (3,6), (4,8) and (5,10) of tenor and coherence
    When the tenor-coherence correlation runs
    Then the coefficient is 1.0
    And the p-value is a number from 0 to 1
    And n is 5

  @fixture
  Scenario: Tied values receive average ranks
    Given tenor values 1, 2, 2, 3 and coherence values 1, 2, 3, 4
    When the tenor-coherence correlation runs
    Then the coefficient is 0.9487 to four decimal places

  Scenario: A pair with either value null is excluded and not counted in n
    Given 6 pairs of which one has a null tenor and one has a null coherence score
    When the tenor-coherence correlation runs
    Then n is 4

  Scenario: The report states coefficient, p-value and n computed from the data
    Given loaded conversations that contain 17 sections with both avg_tenor and semantic_coherence_score non-null
    When the eval:tenor_coherence task runs
    Then the report states a coefficient, a p-value and n equal to 17
    And n equals the count of non-null pairs computed independently from the same data

  # ---------------------------------------------------------------------
  # Rake eval tasks (fact 9; plan step 6)
  # ---------------------------------------------------------------------

  Scenario: Each eval task writes a report under output/eval/
    When eval:tenor_coherence, eval:process_mix and eval:gap_analysis are each run
    Then each run writes a markdown report and a JSON report under output/eval/
    And each report is named after its task

  Scenario: The eval tasks load unseen conversations 11 through 14 from the dataset path
    Given output/eval/nd-11 through output/eval/nd-14 are present
    When eval:process_mix runs
    Then the conversation data is read from output/eval/nd-<n>/conversation_analysis.json for n in 11, 12, 13 and 14
    And the report lists conversations 11, 12, 13 and 14 as used

  Scenario: Missing conversations are named in the report and not silently skipped
    Given output/eval/nd-11 is present and output/eval/nd-12, nd-13 and nd-14 are absent
    When eval:tenor_coherence runs
    Then the task exits with status 0
    And the report lists conversations 12, 13 and 14 as missing
    And the report's n counts only data from conversation 11

  Scenario: The eval task fails loudly when no conversation can be loaded
    Given output/eval/nd-11 through output/eval/nd-14 are all absent
    When eval:gap_analysis runs
    Then the task exits with a non-zero status
    And the message names the dataset path output/eval

  # ---------------------------------------------------------------------
  # TUI analyses tab (fact 12; plan step 7)
  # ---------------------------------------------------------------------

  Scenario: The analyses tab is the fifth tab and is registered in Program::TABS
    When the TUI starts
    Then the tab bar shows five tabs
    And the fifth tab is the analyses tab
    And pressing 5 switches to it

  Scenario: The analyses tab renders the latest report of each analysis
    Given two tenor-coherence reports in output/eval/ with different timestamps
    When the analyses tab renders
    Then it shows the coefficient, p-value and n from the newer report

  Scenario: A missing report is shown as not yet run, naming the rake task that produces it
    Given no gap-analysis report exists in output/eval/
    When the analyses tab renders
    Then the gap-analysis panel shows "not run yet" and names eval:gap_analysis

  Scenario: Pressing a key on the analyses tab returns a new state and at most one command
    When a key event is passed to Program.update with the analyses tab active
    Then the result is a new immutable state
    And at most one command is returned
    And the tab reads no file itself; any read happens inside the command

  # ---------------------------------------------------------------------
  # Logging and config (plan cross-cutting; logging through Ports::Logger)
  # ---------------------------------------------------------------------

  Scenario: A sidecar restart is logged with keyword fields and a fixed message
    Given SFL_LOG_TARGET is "stderr"
    And the sidecar exits once with status 1 during a request
    When the client restarts the sidecar
    Then one log entry carries the fields component "bertopic_sidecar", attempt 1 and exit_status 1
    And the log entry carries the SFL_RUN_ID field
    And the log entry message is a fixed string containing no interpolated values

  Scenario: A coverage retry is logged with attempt, nr_topics, min_topic_size and coverage fields
    Given SFL_LOG_TARGET is "stderr"
    And the first attempt falls below the coverage gate
    When the retry is sent
    Then one log entry carries the fields attempt 2, nr_topics, min_topic_size and coverage
    And the field values are the values sent and measured, not text built into the message

  @journald
  Scenario: With SFL_LOG_TARGET set to stderr and journald the restart log reaches both targets
    Given SFL_LOG_TARGET is "stderr,journald"
    When the client restarts the sidecar
    Then the restart log entry appears on stderr
    And it appears in journalctl with the same SFL_RUN_ID

  # ---------------------------------------------------------------------
  # STRIDE — crossing (a): Ruby <-> sidecar line-delimited JSON
  # ---------------------------------------------------------------------

  @stride @crossing-a
  Scenario: Malformed JSON on stdin is refused without ending the sidecar
    # Tampering, Denial of service
    When the line {"id": "x", "type": "bertopic", "texts": [ is written to stdin
    Then one error line with id null and an "error" message is written
    And the error message does not repeat the malformed line
    When a valid bertopic request is written next
    Then it is answered normally

  @stride @crossing-a
  Scenario: A response whose id does not match the outstanding request is never returned as the result
    # Spoofing, Tampering
    Given the client has sent request "req-7"
    When the sidecar writes a response line with id "req-6" and no line with id "req-7" arrives before the client timeout
    Then the client raises a typed sidecar error
    And the "req-6" response is not returned as a result

  @stride @crossing-a
  Scenario: An oversized request is refused before any byte is written to the sidecar
    # Denial of service
    Given a request whose serialized size exceeds the client's documented maximum request size
    When fit is called with those texts
    Then fit raises a typed error that names the size limit and the measured size
    And the sidecar receives no bytes for that request
    And the sidecar process is still running

  @stride @crossing-a
  Scenario: A sidecar crash mid-request is retried once on a new process and then reported
    # Denial of service, Repudiation
    Given the sidecar exits with status 1 after reading a request and before writing a response
    When fit is called
    Then the client starts a new sidecar process and resends the request once
    And if the second attempt also crashes, fit raises a typed sidecar error that names exit status 1
    And no partial result is returned

  @stride @crossing-a
  Scenario: Texts and embeddings of different lengths are refused before reaching the sidecar
    # Tampering
    When fit is called with 5 texts and 4 embedding vectors
    Then fit raises a typed error that names 5 and 4
    And no bertopic request is written to the sidecar

  # ---------------------------------------------------------------------
  # STRIDE — crossing (b): Ruby -> Ollama embedding HTTP
  # ---------------------------------------------------------------------

  @stride @crossing-b
  Scenario: An unreachable Ollama server fails loudly and names provider, model and endpoint
    # Denial of service, Repudiation
    Given SFL_TASK_EMBEDDING_PROVIDER is "ollama" and SFL_TASK_EMBEDDING_MODEL is "embeddinggemma-2:440m"
    And the configured Ollama endpoint refuses connections
    When the embedding probe runs before a topic fit
    Then a typed embedding error is raised
    And its message names "ollama", "embeddinggemma-2:440m" and the endpoint URL
    And no topic fit is attempted
    And no embeddings are produced

  @stride @crossing-b
  Scenario: An unpulled model fails loudly and tells the operator to pull it
    # Denial of service, Repudiation
    Given the Ollama server is reachable and lists no model named "embeddinggemma-2:440m"
    When the embedding probe runs before a topic fit
    Then a typed embedding error is raised
    And its message names "ollama", "embeddinggemma-2:440m", the endpoint URL and the instruction to run ollama pull
    And no embeddings are produced

  @stride @crossing-b
  Scenario: A reply that is not one vector per text is rejected and never used as embeddings
    # Tampering, Spoofing
    Given the Ollama server answers an embedding request for 5 texts with an error body
    And a second embedding request for 5 texts is answered with 3 vectors
    When each reply is received
    Then each reply raises a typed embedding error
    And neither reply is passed to the sidecar as embeddings
    And no empty embedding vector is produced

  @stride @crossing-b
  Scenario: The embedding call is bounded by the configured timeout
    # Denial of service
    Given SFL_EMBEDDING_TIMEOUT_SECONDS is 2
    And the Ollama server accepts the connection and never responds
    When the embedding probe runs
    Then the call ends within 3 seconds
    And a typed embedding error names the timeout and the endpoint

  @stride @crossing-b
  Scenario: Embedding errors carry provider, model and endpoint but not the section text being embedded
    # Information disclosure
    Given a section whose text contains "CONFIDENTIAL-PHRASE-7731"
    And the Ollama server refuses connections
    When that section is embedded
    Then the raised error names provider, model and endpoint
    And the error message and the log entry do not contain "CONFIDENTIAL-PHRASE-7731"

  # ---------------------------------------------------------------------
  # STRIDE — crossing (c): TopicModeler -> topic_models table
  # ---------------------------------------------------------------------

  @stride @crossing-c
  Scenario: A document key containing SQL metacharacters is stored as literal data
    # Tampering
    Given a fit for document key "x'); DROP TABLE topic_models;--"
    When the fit is stored
    Then the topic_models table still exists
    And one row exists whose document key is that exact string

  @stride @crossing-c
  Scenario: A failed write leaves no partial topic_models row for the run
    # Tampering, Denial of service
    Given the database rejects the insert of topic_words during the store
    When the fit is stored
    Then a typed store error is raised
    And no topic_models row exists for that run id

  @stride @crossing-c
  Scenario: Each stored row carries the run id and timestamps, and no earlier row is overwritten
    # Repudiation
    Given two fits for the same document key are stored by two runs with different SFL_RUN_ID values
    Then two rows exist
    And each row's run id equals the SFL_RUN_ID of the run that wrote it
    And each row has its own created_at value

  # ---------------------------------------------------------------------
  # STRIDE — crossing (d): rake eval tasks -> output/eval/ report files
  # ---------------------------------------------------------------------

  @stride @crossing-d
  Scenario: A conversation argument that is not an integer from 11 to 14 is refused
    # Tampering, Elevation of privilege
    When eval:tenor_coherence is run with CONVERSATIONS "11,../../secrets"
    Then the task exits with a non-zero status
    And the message names the rejected token "../../secrets"
    And no file outside output/eval/nd-<n>/ is read or written

  @stride @crossing-d
  Scenario: A report path that is a symlink is refused and its target is left unchanged
    # Tampering
    Given output/eval/tenor_coherence.md is a symlink to a file outside output/eval/
    When eval:tenor_coherence runs
    Then the task exits with a non-zero status naming the report path
    And the symlink target's content is byte-identical to before the run

  @stride @crossing-d
  Scenario: An interrupted eval run leaves the previous report byte-identical and no partial file
    # Denial of service, Tampering
    Given a previous output/eval/process_mix.md exists
    When eval:process_mix is interrupted with SIGINT while writing
    Then output/eval/process_mix.md is byte-identical to the previous report
    And no temporary or partial report file remains under output/eval/

  @stride @crossing-d
  Scenario: Reports contain aggregates and conversation ids only, never section text
    # Information disclosure
    Given a section whose text contains "CONFIDENTIAL-PHRASE-7731" in conversation 11
    When all three eval tasks run
    Then no report under output/eval/ contains "CONFIDENTIAL-PHRASE-7731"

  # ---------------------------------------------------------------------
  # STRIDE — crossing (e): TUI analyses tab <- reports on disk
  # ---------------------------------------------------------------------

  @stride @crossing-e
  Scenario: A malformed report shows an unreadable notice without crashing the TUI
    # Denial of service
    Given output/eval/tenor_coherence.md is replaced with the text "{not json"
    When the analyses tab renders
    Then the tenor-coherence panel shows "unreadable report"
    And the other panels and tabs keep working

  @stride @crossing-e
  Scenario: Terminal control sequences in a report are rendered as inert text
    # Spoofing, Tampering
    Given a report line containing the escape sequence ESC [2J and an OSC 52 clipboard sequence
    When the analyses tab renders
    Then the sequences are not interpreted by the terminal
    And the screen is not cleared by the report content

  @stride @crossing-e
  Scenario: A symlinked report is not read and the tab says so
    # Elevation of privilege
    Given output/eval/gap_analysis.md is a symlink to a file outside output/eval/
    When the analyses tab renders
    Then the gap-analysis panel shows "refused: symlink"
    And the symlink target's content is not displayed

  @stride @crossing-e
  Scenario: An oversized report is read only up to a fixed byte limit
    # Denial of service
    Given output/eval/process_mix.md is 50 MB
    When the analyses tab renders
    Then at most the fixed byte limit is read
    And the panel shows a truncation notice
