# Design questions 1 (destination), 3 (overwrite/idempotency) and 5 (return
# contract). The incident (4a53727) happened because draft .rb files landed
# in lib/sfl/core/loaders/, which Zeitwerk eager-loads
# (rake zeitwerk:check runs SFL.loader.eager_load) — one bad draft broke
# `bundle exec rake` for the whole repo. Drafts now land in a quarantine the
# runtime never loads, and promotion to lib/ is a human decision expressed as
# a copy, never a code path.
#
# Why docs/ingest-review/candidates/ and not a top-level or nested drafts/
# directory: .gitignore line 41 ignores any directory named drafts/ at any
# depth (verified with git check-ignore), which would hide drafts from
# reviewers; docs/ is committable, is never pushed to a Zeitwerk loader
# (lib/sfl.rb pushes lib/, boot.rb pushes app/), and keeps each draft beside
# its review doc. The .rb suffix is kept (not .rb.txt) so `ruby -c` and
# editor tooling work natively — which REQUIRES one additive config change:
# the quarantine directory must be added to AllCops Exclude in .rubocop.yml,
# because RuboCop's default includes inspect docs/**/*.rb and a broken draft
# there would otherwise fail `rake rubocop` exactly the way the incident
# failed the Zeitwerk check (verified: a fenced .rb under docs/ingest-review/
# candidates/ yields 2 RuboCop offenses today).
@quarantine
Feature: Loader drafts land in a quarantine the runtime never loads

  Background:
    Given the ingest tier SFL::Ingest::LoaderDrafter constructed for the loader_drafting task
    And its default draft destination is docs/ingest-review/candidates
    And its review docs are still written to docs/ingest-review
    And the docs/ingest-review/candidates directory is excluded from RuboCop inspection

  Scenario: A valid draft is written to the quarantine and its paths returned
    When the drafter drafts a candidate for a file the classifier could not recognize
    Then the candidate .rb file exists at docs/ingest-review/candidates/<underscored class name>.rb
    And its companion review doc exists at docs/ingest-review/<underscored class name>.md
    And the draft call returns loader_path pointing at that quarantine .rb file and doc_path pointing at that doc
    And nothing is created, modified or deleted anywhere under lib/

  Scenario: No draft can ever break the repo build again
    Given a corpus of four unrecognized files shaped like the 4a53727 incident
      | file                          | bad draft it produces                     |
      | chat export with fences       | ruby_source containing a ```ruby fence    |
      | misnamed module draft A       | module whose constant misses the path    |
      | misnamed module draft B       | module whose constant misses the path    |
      | undefined-reference draft     | calls methods that are never defined     |
    When the ingest run drafts all four
    Then every draft lands under docs/ingest-review/candidates (or is rejected by the validation gates)
    And `git status lib/sfl/core/loaders/` shows no new or changed files
    And `bundle exec rake` passes: RSpec, RuboCop and the Zeitwerk check are all unaffected by the drafts

  Scenario: The quarantine keeps the .rb suffix so reviewer tooling works
    Given a draft at docs/ingest-review/candidates/generic_jsonl_chat_source.rb
    Then `ruby -c docs/ingest-review/candidates/generic_jsonl_chat_source.rb` prints "Syntax OK"
    And editors highlight the file as Ruby without any special configuration
    And the file ends in .rb, not .rb.txt, so promotion is a plain copy with no rename

  Scenario: Promotion to lib/ is a human copy, never a code path
    Given a reviewed draft at docs/ingest-review/candidates/<stem>.rb and its doc
    When a human reviewer decides the draft is good
    Then they run `ruby -c` on it, copy it to lib/sfl/core/loaders/<stem>.rb, add its mirrored spec and register it in SFL::Ingest::DeterministicRules
    And the drafter itself never writes, requires, loads or registers anything under lib/ at any point
    And the review doc's Status section still says "Not registered" and names the quarantine path plus this promotion recipe

  Scenario: Re-drafting identical content is an idempotent no-op
    Given a draft for class name GenericJsonlChatSource already sits in the quarantine
    When the drafter drafts the same class name again and the LLM returns byte-identical ruby_source
    Then the call succeeds and returns the existing quarantine loader_path and doc_path
    And the existing draft file and doc are not modified and no second file is created

  Scenario: A differing draft for an existing class name fails loudly instead of overwriting
    Given a draft for class name GenericJsonlChatSource already sits in the quarantine
    When the drafter drafts the same class name again and the ruby_source differs
    Then the drafter raises SFL::Ingest::LoaderDrafter::DuplicateDraftError, a subclass of SFL::Ingest::LoaderDrafter::Error
    And the existing draft file and its doc are left untouched
    And nothing is written, no suffixed junk file is created
    And the orchestrator's existing rescue records the file with status "draft_failed" and a reasoning naming the collision, and the run continues

  Scenario: The constructor names the quarantine, not the loaded tree
    When SFL::Ingest::LoaderDrafter is constructed with an lm for the loader_drafting task
    Then it accepts a drafts_dir keyword argument defaulting to docs/ingest-review/candidates
    And it accepts a docs_dir keyword argument defaulting to docs/ingest-review, as today
    And no keyword argument points at lib/sfl/core/loaders and the source file lib/sfl/ingest/loader_drafter.rb contains no reference to that directory
