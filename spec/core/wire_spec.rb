# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe SFL::Core::Wire do
  let(:token) do
    SFL::Core::Types::SyntacticToken.new(
      text: "works", lemma: "work", pos: "VERB", tag: "VBZ",
      dep: "ROOT", head_index: -1, morphology: {}, index: 0
    )
  end

  let(:reasoning_trace) do
    SFL::Core::Types::ReasoningTrace.new(
      premises: [SFL::Core::Types::Premise.new(type: "token", source: "works", value: "VERB", weight: 0.5)],
      inference_rule: "tenor_high_formal_register",
      conclusion: { tenor: 0.7 },
      confidence: 0.9,
      derivation_hash: "a3f2b7c",
      generated_at: Time.now
    )
  end

  let(:annotated_clause) do
    syntactic = SFL::Core::Types::SyntacticClause.new(
      id: "syn-1", text: "It works.", tokens: [token],
      root_index: 0, sentence_index: 0, document_id: "turn-1"
    )
    SFL::Core::Types::AnnotatedClause.new(
      id: "ann-1", text: "It works.", syntactic:,
      ideational: SFL::Core::Types::IdeationalPayload.new(
        clause_id: "syn-1", process_type: "material",
        participants: [], circumstances: [], raw_transitivity: {}
      ),
      interpersonal: SFL::Core::Types::InterpersonalPayload.new(
        clause_id: "syn-1", mood: "declarative",
        modality_weight: 0.6, tenor: 0.7,
        speaker_attitude: nil, reasoning: nil,
        annotation_source: "llm", reasoning_trace:
      ),
      document_id: "turn-1", compiled_at: Time.now
    )
  end

  let(:turn) do
    SFL::Core::Types::ConversationTurn.new(
      turn_id: 1, speaker: "Alice", timestamp: Time.now,
      message_text: "It works.", clauses: [annotated_clause],
      avg_tenor: 0.7, avg_modality: 0.6, dominant_mood: "declarative",
      process_types: { "material" => 1 }, participants: [], tenor_shift: nil
    )
  end

  describe ".dump" do
    it "stringifies every Time attribute to ISO8601, recursively" do
      dumped = described_class.dump(annotated_clause)

      expect(dumped[:compiled_at]).to be_a(String)
      expect(dumped[:interpersonal][:reasoning_trace][:generated_at]).to be_a(String)
      expect { Time.parse(dumped[:compiled_at]) }.not_to raise_error
    end
  end

  describe "AnnotatedClause round trip" do
    it "survives a real JSON round trip with the same field values, including a nested reasoning_trace" do
      json = JSON.generate(described_class.dump(annotated_clause))
      hash = JSON.parse(json, symbolize_names: true)
      reloaded = described_class.load_annotated_clause(hash)

      expect(reloaded.id).to eq(annotated_clause.id)
      expect(reloaded.compiled_at.to_i).to eq(annotated_clause.compiled_at.to_i)
      expect(reloaded.syntactic.tokens.first.text).to eq("works")
      expect(reloaded.interpersonal.reasoning_trace.inference_rule).to eq("tenor_high_formal_register")
      expect(reloaded.interpersonal.reasoning_trace.generated_at.to_i).to eq(reasoning_trace.generated_at.to_i)
    end

    it "survives a round trip when reasoning_trace is nil" do
      clause = annotated_clause.new(
        interpersonal: annotated_clause.interpersonal.new(reasoning_trace: nil)
      )
      json = JSON.generate(described_class.dump(clause))
      hash = JSON.parse(json, symbolize_names: true)
      reloaded = described_class.load_annotated_clause(hash)

      expect(reloaded.interpersonal.reasoning_trace).to be_nil
    end
  end

  describe "ConversationTurn round trip" do
    it "survives a real JSON round trip with nested clauses intact" do
      json = JSON.generate(described_class.dump(turn))
      hash = JSON.parse(json, symbolize_names: true)
      reloaded = described_class.load_conversation_turn(hash)

      expect(reloaded.turn_id).to eq(turn.turn_id)
      expect(reloaded.speaker).to eq(turn.speaker)
      expect(reloaded.timestamp.to_i).to eq(turn.timestamp.to_i)
      expect(reloaded.avg_tenor).to eq(turn.avg_tenor)
      expect(reloaded.clauses.size).to eq(1)
      expect(reloaded.clauses.first.id).to eq(annotated_clause.id)
    end
  end

  describe "AnalysisResult round trip" do
    let(:profile) do
      SFL::Core::Types::SpeakerProfile.new(
        speaker_name: "Alice", turn_count: 1,
        avg_tenor: 0.6, tenor_range: [0.5, 0.7], tenor_variance: 0.01,
        avg_modality: 0.55, mood_distribution: { "declarative" => 1 }, dominant_processes: {}
      )
    end

    let(:key_moment) do
      SFL::Core::Types::KeyMoment.new(
        turn_id: 1, type: "tenor_shift", magnitude: 0.25, description: "shift up"
      )
    end

    let(:example_passage) do
      SFL::Core::Types::ExamplePassage.new(
        label: "Most Formal", text: "Hello.", speaker: "Alice", value: 0.8, reason: "highest tenor"
      )
    end

    let(:result) do
      SFL::Core::Types::AnalysisResult.new(
        metadata: { conversation_id: "test", analyzed_at: Time.now.iso8601 },
        turns: [turn],
        speaker_profiles: { "Alice" => profile },
        tenor_timeline: [{ turn_id: 1, tenor: 0.6 }],
        field_evolution: [{ turn_id: 1, dominant_process: "material" }],
        correlations: {},
        insights: ["one insight"],
        key_moments: [key_moment],
        example_passages: [example_passage]
      )
    end

    it "survives a real JSON round trip with speaker_profiles, key_moments, and example_passages intact" do
      json = JSON.generate(described_class.dump(result))
      hash = JSON.parse(json, symbolize_names: true)
      reloaded = described_class.load_analysis_result(hash)

      expect(reloaded.turns.size).to eq(1)
      expect(reloaded.turns.first.speaker).to eq("Alice")
      expect(reloaded.speaker_profiles["Alice"]).to be_a(SFL::Core::Types::SpeakerProfile)
      expect(reloaded.speaker_profiles["Alice"].avg_tenor).to eq(0.6)
      expect(reloaded.key_moments.first).to be_a(SFL::Core::Types::KeyMoment)
      expect(reloaded.example_passages.first).to be_a(SFL::Core::Types::ExamplePassage)
      expect(reloaded.insights).to eq(["one insight"])
    end
  end
end
