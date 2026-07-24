# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Formatters::MarkdownFormatter do
  subject(:markdown) { described_class.new(result).render }

  let(:cohesion) { SFL::Core::Types::CohesionMetrics.new(repetition_score: 0.2, conjunction_density: 0.1, pronoun_density: 0.3) }
  let(:turn) { build_turn(turn_id: 1, speaker: "Alice") }
  let(:metadata) { { conversation_id: "conv-1", analyzed_at: "2024-01-01", turn_count: 1, speakers: ["Alice"] } }
  let(:speaker_profile) do
    SFL::Core::Types::SpeakerProfile.new(
      speaker_name: "Alice", turn_count: 1, avg_tenor: 0.6, tenor_range: [0.5, 0.7], tenor_variance: 0.01,
      avg_modality: 0.5, mood_distribution: { "declarative" => 1 }, dominant_processes: { "material" => 1 }
    )
  end
  let(:result) do
    build_analysis_result(metadata:, turns: [turn], speaker_profiles: { "Alice" => speaker_profile },
      insights: ["Insight one."])
  end

  it "renders the conversation id, turn/speaker counts, and summary section" do
    expect(markdown).to include("# Conversation Analysis: conv-1")
    expect(markdown).to include("**Turns**: 1 | **Speakers**: Alice")
    expect(markdown).to include("## Summary")
  end

  it "renders a speaker profile row" do
    expect(markdown).to include("| Alice ")
    expect(markdown).to include("0.6 (mixed)")
  end

  it "renders the low confidence banner only when metadata[:low_confidence] is set" do
    expect(markdown).not_to include("LOW CONFIDENCE")

    flagged = build_analysis_result(
      metadata: metadata.merge(low_confidence: true, clause_count: 2, low_confidence_threshold: 10),
      turns: [turn], speaker_profiles: { "Alice" => speaker_profile }
    )

    expect(described_class.new(flagged).render).to include("🚨 LOW CONFIDENCE: 2 clauses (minimum 10 recommended)")
  end

  it "renders a data quality warning when clauses carry fallback/stub annotation sources" do
    fallback_clause = build_annotated_clause(annotation_source: "fallback")
    turn_with_fallback = build_turn(clauses: [fallback_clause])
    flagged = build_analysis_result(metadata:, turns: [turn_with_fallback], speaker_profiles: {})

    expect(described_class.new(flagged).render).to include("## ⚠️ Data Quality")
  end

  it "renders cohesion metrics when a turn has cohesion data" do
    turn_with_cohesion = build_turn(turn_id: 2, speaker: "Bob")
    turn_with_cohesion = turn_with_cohesion.new(cohesion:)
    with_cohesion = build_analysis_result(metadata:, turns: [turn_with_cohesion], speaker_profiles: {})

    expect(described_class.new(with_cohesion).render).to include("| 2 | Bob | 0.2 | 0.1 | 0.3 |")
  end

  it "renders reasoning traces for clauses that have one and omits it for those that don't" do
    trace = build_reasoning_trace(inference_rule: "modal_verb_strength")
    traced_clause = build_annotated_clause(annotation_source: "llm")
    traced_clause = traced_clause.new(interpersonal: traced_clause.interpersonal.new(reasoning_trace: trace))
    turn_with_trace = build_turn(clauses: [traced_clause])
    with_trace = build_analysis_result(metadata:, turns: [turn_with_trace], speaker_profiles: {})

    expect(described_class.new(with_trace).render).to include("### 🔍 Reasoning Traces")
    expect(described_class.new(with_trace).render).to include("Reasoning: modal_verb_strength")
  end

  it "does not render a sprint footer (GEB-sprint machinery is out of scope)" do
    with_sprint_meta = build_analysis_result(
      metadata: metadata.merge(sprint_id: "sprint-1", sprint_question_ids: ["q1"]),
      turns: [turn], speaker_profiles: {}
    )

    expect(described_class.new(with_sprint_meta).render).not_to include("Sprint ID")
  end
end
