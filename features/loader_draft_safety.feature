# Design question 7 — STRIDE. The drafter crosses three trust boundaries:
#   X1  the LLM response becomes file content (network output -> disk)
#   X2  that content is written into the shared repository tree
#   X3  after human review, the draft becomes executable code by promotion
# One misuse scenario is written per crossing, plus one for the elevation of
# privilege that promotion would otherwise be. The core invariant behind
# all four: the drafter treats LLM output as untrusted DATA — it is parsed,
# written and documented, never executed, required, eval'd or registered.
@stride
Feature: Loader drafting resists misuse of LLM output

  Background:
    Given SFL::Ingest::LoaderDrafter is a last-resort tier whose input is untrusted LLM output
    And its drafts exist to be human-reviewed, never to run
    And every draft lands in the docs/ingest-review/candidates quarantine

  # X1 — Tampering: malicious or corrupted ruby_source must never execute
  Scenario: Malicious draft content is quarantined as data, never executed
    When the predictor returns ruby_source containing `system("rm -rf /")`, a `eval` of LLM text, a network call, a file deletion or a require of repo files
    Then the drafter neither executes, requires, loads nor evals that source at any point — validation is AbstractSyntaxTree parsing only
    And the content, when its syntax and naming pass the gates, is written verbatim into the quarantine as inert text
    And a human reviewer reading the doc sees the exact content, and promotion remains a conscious human act that such content must survive

  # X2 — Repudiation: every draft and every failure must be attributable
  Scenario: Every draft and failure is attributable to its source and run
    When a draft is written or rejected during a run
    Then the review doc records the original file's path, the class name, the confidence and the outcome (written or which gate failed)
    And a rejection raises an Error whose message names the source file and the gate, which the orchestrator logs at the boundary with the file field and the run's SFL_RUN_ID
    And a successful draft is recorded by the orchestrator as a "loader_drafted" review entry carrying both returned paths, so no draft can exist without a traceable origin

  # X2 — Denial of service: bad LLM output must fail bounded
  Scenario: A corpus of invalid drafts fails bounded, with no retry storm and no junk accumulation
    When a run ingests any number of files whose drafts all fail the gates or collide with existing drafts
    Then each file costs exactly one predictor call and either one quarantined draft or one review entry, and the run completes
    And repeated re-runs of the same corpus create no suffixed duplicates and never overwrite existing drafts
    And the quarantine directory grows only when genuinely new class names are drafted

  # X3 — Elevation of privilege at the promotion boundary
  Scenario: Nothing is ever auto-registered or auto-loaded
    When any number of drafts sits in the quarantine for any length of time
    Then no ingest run, rake task or boot path requires, loads or registers any of them — the Zeitwerk loader never sees the docs/ tree
    And the review doc's Status section still says "Not registered" with the promotion recipe, so a draft becomes code only when a human copies it into lib/, adds its mirrored spec and registers it in DeterministicRules
    And an INVALID draft's doc says "INVALID — do not promote", so the promotion boundary is labeled even for drafts the gates rejected
