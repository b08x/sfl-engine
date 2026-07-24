# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Prompts do
  let(:two_clauses) do
    [
      {
        index: 0,
        text: "First.",
        root_verb: "a",
        process_type: "material",
        participants: "p",
        pos_tags: "t",
        dependencies: "d",
      },
      {
        index: 1,
        text: "Second.",
        root_verb: "b",
        process_type: "mental",
        participants: "p2",
        pos_tags: "t2",
        dependencies: "d2",
      },
    ]
  end

  describe ".render" do
    it "renders the pass_two_annotation template with the given vars" do
      text = described_class.render(
        :pass_two_annotation,
        text: "It works.", root_verb: "works", process_type: "material",
        participants: "system", pos_tags: "It/PRP works/VBZ", dependencies: "It<nsubj works<ROOT",
        semantic_coherence_score: nil
      )

      expect(text).to include("Text: It works.")
      expect(text).to include("Root verb: works")
      expect(text).not_to include("Semantic coherence score")
    end

    it "includes the semantic coherence line only when a score is given" do
      text = described_class.render(
        :pass_two_annotation,
        text: "x", root_verb: "x", process_type: "x", participants: "x",
        pos_tags: "x", dependencies: "x", semantic_coherence_score: 0.42
      )

      expect(text).to include("0.42")
    end

    it "renders the pass_two_batch_annotation template with multiple clauses" do
      text = described_class.render(:pass_two_batch_annotation, clauses: two_clauses)

      expect(text).to include("### Clause 0")
      expect(text).to include("Text: First.")
      expect(text).to include("### Clause 1")
      expect(text).to include("Text: Second.")
    end

    it "raises ArgumentError for an unknown template name" do
      expect { described_class.render(:does_not_exist) }.to raise_error(ArgumentError, /does_not_exist/)
    end
  end
end
