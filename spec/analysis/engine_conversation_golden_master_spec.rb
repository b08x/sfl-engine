# frozen_string_literal: true

require "spec_helper"
require "json"

# Regression proof for the D2 compile-loop unification: runs
# Analysis::Engine + ConversationSource against the same input legacy's
# CLI used to generate spec/fixtures/golden_master/conversation/, in the
# equivalent pass1-only stub mode, and diffs the resulting
# Core::Types::AnalysisResult against the golden master's per-turn values
# (excluding metadata.analyzed_at, which is never stable across runs).
#
# The golden-master JSON itself is legacy CLI *report* output (previews,
# annotation_coverage, per-clause ids) — a formatter this codebase hasn't
# built yet (that's Phase 4/CLI work), not a Wire.dump of AnalysisResult.
# This spec therefore diffs at the AnalysisResult-structural level: every
# field the golden master's turns[] carries that AnalysisResult's own
# ConversationTurn also carries (avg_tenor, avg_modality, dominant_mood,
# tenor_shift, clause counts, dominant_topic, semantic_coherence_score) —
# see the Data Pipeline Engineer's final report for why a byte-exact CLI
# JSON diff isn't in scope for this slice.
#
# Pass 1 is stubbed with a plain double (not the real spaCy sidecar,
# unavailable in this sandbox) that reproduces the golden master's own
# per-turn clause counts (1,2,1,2,2 = 8 total) — sufficient to prove the
# Engine/Source/Pipeline wiring, independent of real linguistic parsing.
# No real LLM/network calls anywhere in this spec: pass_one_only: true
# means Pipeline never even constructs a Pass 2 annotator.
# rubocop:disable RSpec/DescribeClass -- exercises the Engine/ConversationSource/Pipeline
# collaboration as a whole against a golden-master fixture, not one class's unit contract.
RSpec.describe "Analysis::Engine conversation golden master" do
  subject(:result) do
    engine.analyze(source, label: "sample", store: false, resume: false, topics: 3, pass_one_only: true)
  end

  let(:golden_master) do
    JSON.parse(
      File.read("spec/fixtures/golden_master/conversation/conversation_analysis.json"),
      symbolize_names: true
    )
  end

  let(:clause_counts) { golden_master[:turns].map { |t| t[:clause_count] } }

  let(:pass_one) do
    counts = clause_counts
    calls = 0
    instance_double(SFL::Core::PassOne::Engine).tap do |dbl|
      allow(dbl).to receive(:process) do |text, document_id:|
        n = counts[calls]
        calls += 1
        Array.new(n) do |i|
          SFL::Core::Types::SyntacticClause.new(
            id: "#{document_id}-syn-#{i}", text:, tokens: [], root_index: 0,
            sentence_index: i, document_id:
          )
        end
      end
    end
  end

  let(:ideational_extractor) do
    instance_double(SFL::Core::PassOne::IdeationalExtractor).tap do |dbl|
      allow(dbl).to receive(:extract) do |clause|
        SFL::Core::Types::IdeationalPayload.new(
          clause_id: clause.id, process_type: "material", participants: [], circumstances: [], raw_transitivity: {}
        )
      end
    end
  end

  let(:pass_two) { instance_double(SFL::Core::Ports::Annotator) }

  let(:pipeline) { SFL::Core::Pipeline.new(pass_one:, pass_two:, ideational_extractor:) }
  let(:engine) { SFL::Analysis::Engine.new(pipeline:) }
  let(:source) { SFL::Analysis::ConversationSource.new("spec/fixtures/inputs/sample.jsonl") }

  it "never calls Pass 2 (proves the documentation golden-master bug's fix generalizes)" do
    allow(pass_two).to receive(:annotate_batch)

    result

    expect(pass_two).not_to have_received(:annotate_batch)
  end

  it "matches the golden master's turn count and speakers" do
    expect(result.turns.size).to eq(golden_master[:metadata][:turn_count])
    expect(result.turns.map(&:speaker).uniq).to eq(golden_master[:metadata][:speakers])
  end

  # rubocop:disable RSpec/MultipleExpectations -- one golden-master turn diffed field-by-field;
  # itemized expectations pinpoint exactly which field regressed instead of collapsing to one
  # opaque Hash#== failure.
  it "matches every golden-master turn's stub-mode field values" do
    golden_master[:turns].each_with_index do |expected, idx|
      turn = result.turns[idx]

      expect(turn.turn_id).to eq(expected[:turn_id])
      expect(turn.speaker).to eq(expected[:speaker])
      expect(turn.timestamp.iso8601).to eq(expected[:timestamp])
      expect(turn.avg_tenor).to eq(expected[:avg_tenor])
      expect(turn.avg_modality).to eq(expected[:avg_modality])
      expect(turn.dominant_mood).to eq(expected[:dominant_mood])
      expect(turn.tenor_shift).to eq(expected[:tenor_shift])
      expect(turn.clauses.size).to eq(expected[:clause_count])
      expect(turn.dominant_topic).to eq(expected[:dominant_topic])
      expect(turn.semantic_coherence_score).to eq(expected[:semantic_coherence_score])
      expect(turn.clauses.map { |c| c.interpersonal.annotation_source }.uniq).to eq(["stub"])
    end
  end
  # rubocop:enable RSpec/MultipleExpectations

  it "stubs every clause with a neutral InterpersonalPayload, matching --pass1-only stub mode" do
    result.turns.flat_map(&:clauses).each do |clause|
      expect(clause.interpersonal.mood).to eq("declarative")
      expect(clause.interpersonal.modality_weight).to eq(0.5)
      expect(clause.interpersonal.tenor).to eq(0.5)
      expect(clause.interpersonal.annotation_source).to eq("stub")
      expect(clause.textual.topical_theme).to be_nil
    end
  end
end
# rubocop:enable RSpec/DescribeClass
