# Design question 2 (validation gates) and the AGENTS.md convention
# violation (spec/ingest/loader_drafter_spec.rb does not exist — every lib
# file has a mirrored spec). Today the only gate is CLASS_NAME_PATTERN on the
# class name; the LLM's ruby_source is written to disk sight unseen. Three
# gates now run, in order, BEFORE any .rb file is written:
#
#   G1  class_name matches CLASS_NAME_PATTERN (today's behavior, kept)
#   G2  ruby_source parses as Ruby syntax, via RubyVM::AbstractSyntaxTree.parse
#       — a parse, never an eval, a require or a load
#   G3  the parsed source declares class <class_name> under the
#       SFL::Core::Loaders namespace — so that a promotion-by-copy to
#       lib/sfl/core/loaders/<underscore(class_name)>.rb would define exactly
#       the constant Zeitwerk expects. The file-name side of Zeitwerk
#       consistency is automatic (the stem is derived from class_name); the
#       real gate is the constant declared inside the source.
#
# An invalid draft (G2 or G3) writes NO .rb file anywhere, writes an evidence
# doc named <stem>-invalid.md (the -invalid suffix guarantees it can never
# overwrite a valid draft's doc), and raises LoaderDrafter::Error so the
# orchestrator's existing rescue records status "draft_failed". The drafter
# does not repair LLM output (no fence stripping) and does not retry the
# predictor — it is a last-resort tier, and a retry storm on a bad prompt is
# a self-inflicted denial of service.
@validation
Feature: Drafts pass three validation gates before anything is written

  Background:
    Given a draft response from the loader_drafting predictor with class_name, ruby_source, field_mapping_explanation and confidence fields
    And the drafter's quarantine destination docs/ingest-review/candidates

  Scenario: A fully valid draft passes all three gates and is written
    When the predictor returns class_name GenericJsonlChatSource and ruby_source declaring class GenericJsonlChatSource under SFL::Core::Loaders
    Then all three gates pass in order: the class-name pattern, the syntax parse and the declared-constant check
    And the draft .rb is written to the quarantine and the review doc to docs/ingest-review, as in the quarantine feature

  Scenario: A malformed class name is rejected and nothing is written
    When the predictor returns class_name "generic jsonl source" or "Transcription_Loader" or "transcriptionLoader"
    Then gate G1 raises SFL::Ingest::LoaderDrafter::Error naming the file and the invalid class name, exactly as today
    And no draft file and no doc are written

  Scenario: Unparseable ruby_source is rejected — the incident's markdown fence
    When the predictor returns ruby_source containing a literal ```ruby markdown fence or any other syntax error
    Then gate G2 rejects it through AbstractSyntaxTree parsing, and the drafter never evals, requires or loads the source to find out
    And no .rb file is written anywhere
    And the failure raises SFL::Ingest::LoaderDrafter::Error whose message names the syntax gate and the source path

  Scenario: A source whose declared constant would violate Zeitwerk naming is rejected
    When the predictor returns class_name TranscriptionLoader but ruby_source declares module TranscriptionLoader, or declares class TranscriptionLoader at the top level with no SFL::Core::Loaders namespace, or declares class TranscriptionTextLoader
    Then gate G3 rejects it, because a promotion-by-copy to lib/sfl/core/loaders/transcription_loader.rb would define a constant Zeitwerk cannot resolve
    And no .rb file is written anywhere
    And the failure raises SFL::Ingest::LoaderDrafter::Error whose message names the naming gate and the mismatch

  Scenario: An invalid draft leaves evidence for the human reviewer, not an executable-shaped file
    When gate G2 or G3 rejects a draft whose class_name itself is valid
    Then the drafter writes a doc named <underscored class name>-invalid.md under docs/ingest-review
    And the doc's Status section says "INVALID — do not promote" and names which gate failed and why
    And the doc embeds the raw rejected ruby_source in a fenced code block, so the reviewer sees exactly what the LLM produced
    And the drafter then raises SFL::Ingest::LoaderDrafter::Error, and the orchestrator records the file with status "draft_failed" and the run continues
    And the -invalid.md doc never overwrites an existing valid draft's doc or .rb file

  Scenario: No repair and no retry — one predictor call per draft
    When the predictor returns a fenced or otherwise invalid draft
    Then the drafter calls the predictor exactly once for that draft
    And it does not strip fences, unwrap markdown or otherwise silently mutate the LLM output before validating
    And the draft call fails after a bounded number of steps, so a run over a corpus of unrecognized files cannot loop

  Scenario: The drafter has the mirrored spec the AGENTS.md convention requires
    Given the convention that every file under lib/ has a spec at the matching path under spec/
    When spec/ingest/loader_drafter_spec.rb is created
    Then it exists for lib/sfl/ingest/loader_drafter.rb and passes
    And it drives the drafter through an injected predictor double, making no network or LLM call
    And it covers: the quarantine destination (never lib/sfl/core/loaders), all three gates with one invalid fixture each, the -invalid.md evidence doc, the raised error hierarchy, the idempotent identical re-draft, the differing-draft DuplicateDraftError, and the returned loader_path and doc_path pair
