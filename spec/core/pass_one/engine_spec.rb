# frozen_string_literal: true

RSpec.describe "SFL::Core::PassOne::Engine", pending: "Phase 1: sidecar Pass 1 engine not yet implemented" do
  # Characterization spec per Phase 0 (trackboi decision 2 / blueprint F1): pins the head-index
  # resolution contract the Python sidecar must satisfy. The legacy PassOneEngine resolves a
  # token's head by looking up `local_idx[token.head.text]` -- a TEXT-keyed hash -- so on a
  # sentence with a repeated word, every duplicate's dependents resolve to the FIRST occurrence
  # of that word instead of the correct one. The sidecar fixes this structurally by carrying
  # spaCy's native positional `token.i` (offset from `sent.start`) instead of a text lookup.
  #
  # This spec is intentionally unimplementable until Phase 1 ships `SFL::Core::PassOne::Engine`
  # and its `SyntacticParser` port/sidecar client -- it exists now to pin the acceptance
  # criterion before any code is written (TDD red, not yet green).

  it "resolves head_index positionally, not by matching head token text" do
    skip "implement once SFL::Core::PassOne::Engine + SpacySidecarParser exist (Phase 1)"

    # sentence = "the dog chased the cat"
    # both "the" tokens must NOT collapse to the same head_index; "cat"'s head ("chased")
    # must resolve correctly even though "chased" is not the first token in the sentence,
    # and neither "the" may be misclassified as ROOT via a text-match false positive.
  end
end
