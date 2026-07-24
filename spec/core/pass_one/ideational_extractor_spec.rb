# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::PassOne::IdeationalExtractor do
  subject(:extractor) { described_class.new }

  def token(text:, lemma:, pos: "VERB", tag: "VBZ", dep: "ROOT", index: 0) # rubocop:disable Metrics/ParameterLists -- one keyword per SyntacticToken attribute this helper builds
    SFL::Core::Types::SyntacticToken.new(text:, lemma:, pos:, tag:, dep:, head_index: -1, morphology: {}, index:)
  end

  def clause_with(text:, tokens:, root_index: 0)
    SFL::Core::Types::SyntacticClause.new(
      id: "c-1", text:, tokens:, root_index:, sentence_index: 0, document_id: "doc-1"
    )
  end

  describe "#extract" do
    it "returns the empty/material default when the clause has no root token" do
      clause = clause_with(text: "x", tokens: [], root_index: 0)

      result = extractor.extract(clause)

      expect(result.process_type).to eq("material")
      expect(result.participants).to eq([])
      expect(result.circumstances).to eq([])
      expect(result.raw_transitivity).to eq({})
    end

    describe "process classification" do
      it "classifies a mental-verb root as mental" do
        root = token(text: "thinks", lemma: "think")
        result = extractor.extract(clause_with(text: "She thinks.", tokens: [root]))

        expect(result.process_type).to eq("mental")
      end

      it "classifies a verbal-verb root as verbal (checked before behavioral/existential)" do
        root = token(text: "said", lemma: "say")
        result = extractor.extract(clause_with(text: "She said.", tokens: [root]))

        expect(result.process_type).to eq("verbal")
      end

      it "classifies a behavioral-verb root as behavioral" do
        root = token(text: "laughed", lemma: "laugh")
        result = extractor.extract(clause_with(text: "She laughed.", tokens: [root]))

        expect(result.process_type).to eq("behavioral")
      end

      it "classifies an unrecognized VBZ-tagged root as material by default" do
        root = token(text: "runs", lemma: "run", tag: "VBZ")
        result = extractor.extract(clause_with(text: "It runs.", tokens: [root]))

        expect(result.process_type).to eq("material")
      end

      it "classifies a modal auxiliary root as mental via PROCESS_INDICATORS" do
        root = token(text: "must", lemma: "must", tag: "MD")
        result = extractor.extract(clause_with(text: "It must.", tokens: [root]))

        expect(result.process_type).to eq("mental")
      end

      # "be" is both a RELATIONAL_VERBS and EXISTENTIAL_VERBS entry, and
      # relational is checked first — ported unchanged from the legacy
      # extractor (decision: logic unchanged), so this pins the existing
      # behavior rather than the SFL-ideal one.
      it "classifies a 'there is/are' clause rooted in 'be' as relational, not existential" do
        root = token(text: "are", lemma: "be")
        result = extractor.extract(clause_with(text: "There are three options.", tokens: [root]))

        expect(result.process_type).to eq("relational")
      end

      it "classifies a 'there exists' clause as existential" do
        root = token(text: "exists", lemma: "exist")
        result = extractor.extract(clause_with(text: "There exists a solution.", tokens: [root]))

        expect(result.process_type).to eq("existential")
      end
    end

    describe "participants and circumstances" do
      it "maps nsubj to Actor and dobj to Goal, excluding Circumstance-role deps from participants" do
        root = token(text: "approved", lemma: "approve", index: 1)
        subj = token(text: "committee", lemma: "committee", pos: "NOUN", tag: "NN", dep: "nsubj", index: 0)
        obj = token(text: "budget", lemma: "budget", pos: "NOUN", tag: "NN", dep: "dobj", index: 2)
        prep = token(text: "today", lemma: "today", pos: "NOUN", tag: "NN", dep: "advmod", index: 3)

        result = extractor.extract(clause_with(text: "x", tokens: [subj, root, obj, prep], root_index: 1))

        expect(result.participants.map { |p| [p.role, p.text] }).to contain_exactly(
          %w[Actor committee], %w[Goal budget]
        )
        expect(result.circumstances).to eq(["advmod:today"])
      end

      it "returns no participants or circumstances for deps with no PARTICIPANT_ROLES mapping" do
        root = token(text: "ran", lemma: "run", index: 1)
        punct = token(text: ".", lemma: ".", pos: "PUNCT", tag: ".", dep: "punct", index: 2)

        result = extractor.extract(clause_with(text: "x", tokens: [root, punct], root_index: 0))

        expect(result.participants).to eq([])
        expect(result.circumstances).to eq([])
      end
    end

    describe "raw_transitivity" do
      it "includes the root token and every token's text/dep/pos/tag" do
        root = token(text: "ran", lemma: "run", pos: "VERB", tag: "VBD", index: 0)
        result = extractor.extract(clause_with(text: "x", tokens: [root]))

        expect(result.raw_transitivity[:root]).to eq(text: "ran", lemma: "run", pos: "VERB", tag: "VBD")
        expect(result.raw_transitivity[:dependencies]).to eq([{ text: "ran", dep: "ROOT", pos: "VERB", tag: "VBD" }])
      end
    end
  end
end
