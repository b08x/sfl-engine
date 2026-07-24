# frozen_string_literal: true

require "spec_helper"
require "dry/monads"

# Targets the branches spec/analysis/engine_conversation_golden_master_spec.rb's happy path
# never exercises. #build_result is public (see its own doc comment — deliberately, for a future
# fan-in job) so most of these drive it directly with hand-built ConversationTurn arrays instead
# of going through #analyze/Pipeline#compile; only the compile-loop-specific branches
# (enqueue_review, fit_topics, report_progress, stop_requested) need #analyze plus a stubbed
# Pipeline. Doubles follow the golden-master spec's own convention: instance_double for real
# classes, plain doubles for ducks with no single verifiable class (Source, the injectable
# topic_modeler_factory).
RSpec.describe SFL::Analysis::Engine do
  include Dry::Monads[:result]

  # FakeAnalysisSource (the #units/#review_entry/#extra_metadata duck) lives in
  # spec/support/fake_analysis_source.rb.

  def build_unit(id, text: "hello", speaker: "Alice")
    SFL::Core::Types::Unit.new(document_id: id, text:, speaker:, is_user: nil, sent_at: nil, metadata: {})
  end

  let(:pipeline) { instance_double(SFL::Core::Pipeline) }
  let(:engine) { described_class.new(pipeline:) }
  let(:no_op_source) { FakeAnalysisSource.new([], extra: {}) }

  describe "#build_result -> apply_chunk_artifacts (the third optional Source hook)" do
    # Boundary at flat index 2: clause[1] ("The system was", tenor 0.5) has no terminal
    # punctuation and clause[2] ("designed for scale.", tenor 0.5) starts lowercase — a
    # real mid-sentence PDF chunk split, per ChunkArtifactDetector's own heuristic.
    let(:turn_before_split) do
      build_turn(turn_id: 1, avg_tenor: 0.65, avg_modality: 0.65, clauses: [
        build_annotated_clause(id: "c1", text: "Solid opener.", tenor: 0.8, modality: 0.8),
        build_annotated_clause(id: "c2", text: "The system was", tenor: 0.5, modality: 0.5),
      ])
    end
    let(:turn_after_split) do
      build_turn(turn_id: 2, avg_tenor: 0.35, avg_modality: 0.55, clauses: [
        build_annotated_clause(id: "c3", text: "designed for scale.", tenor: 0.5, modality: 0.5),
        build_annotated_clause(id: "c4", text: "Solid closer.", tenor: 0.2, modality: 0.6),
      ])
    end
    let(:chunk_boundary_source) do
      source = FakeAnalysisSource.new([], extra: {})
      def source.chunk_boundaries(_turns) = [2]
      source
    end

    it "leaves turns untouched when the source doesn't implement #chunk_boundaries" do
      turns = [build_turn(turn_id: 1, clauses: [build_annotated_clause])]

      result = engine.build_result(turns, source: no_op_source, label: "x", total: 1)

      expect(result.turns.first.clauses.first.interpersonal.annotation_source).to eq("llm")
    end

    it "leaves turns untouched when #chunk_boundaries returns []" do
      source = FakeAnalysisSource.new([], extra: {})
      def source.chunk_boundaries(_turns) = []
      turns = [build_turn(turn_id: 1, clauses: [build_annotated_clause])]

      result = engine.build_result(turns, source:, label: "x", total: 1)

      expect(result.turns.first.clauses.first.interpersonal.annotation_source).to eq("llm")
    end

    it "marks the flagged clauses chunk_artifact and excludes them from that turn's " \
      "avg_tenor/avg_modality, without touching turns the boundary doesn't reach" do
      result = engine.build_result(
        [turn_before_split, turn_after_split], source: chunk_boundary_source, label: "x", total: 2
      )

      rebuilt1, rebuilt2 = result.turns
      expect(rebuilt1.clauses.map { |c| c.interpersonal.annotation_source }).to eq(%w[llm chunk_artifact])
      expect(rebuilt2.clauses.map { |c| c.interpersonal.annotation_source }).to eq(%w[chunk_artifact llm])
      expect(rebuilt1.avg_tenor).to eq(0.8)
      expect(rebuilt1.avg_modality).to eq(0.8)
      expect(rebuilt2.avg_tenor).to eq(0.2)
      expect(rebuilt2.avg_modality).to eq(0.6)
    end

    it "a real DocumentationSource over pure-markdown input never marks any clause chunk_artifact " \
      "(chunk_boundaries returns [] by construction — see documentation_source_spec.rb)" do
      source = SFL::Analysis::DocumentationSource.new("spec/fixtures/inputs/sample.md")
      source.units # populate the source's internal unit-tracking before the hook is queried
      turns = [
        build_turn(turn_id: 1, clauses: [build_annotated_clause(id: "c1")]),
        build_turn(turn_id: 2, clauses: [build_annotated_clause(id: "c2")]),
      ]

      result = engine.build_result(turns, source:, label: "x", total: 2)

      annotation_sources = result.turns.flat_map(&:clauses).map { |c| c.interpersonal.annotation_source }
      expect(annotation_sources).to eq(%w[llm llm])
    end
  end

  describe "#build_result -> detect_key_moments" do
    it "emits a tenor_shift moment when the consecutive-turn delta exceeds 0.15" do
      turns = [build_turn(turn_id: 1, avg_tenor: 0.2), build_turn(turn_id: 2, avg_tenor: 0.4)]

      result = engine.build_result(turns, source: no_op_source, label: "x", total: 2)

      moment = result.key_moments.find { |m| m.type == "tenor_shift" }
      expect(moment.magnitude).to eq(0.2)
    end

    it "does not emit a tenor_shift moment at or below the 0.15 threshold" do
      turns = [build_turn(turn_id: 1, avg_tenor: 0.4), build_turn(turn_id: 2, avg_tenor: 0.5)]

      result = engine.build_result(turns, source: no_op_source, label: "x", total: 2)

      expect(result.key_moments.map(&:type)).not_to include("tenor_shift")
    end

    it "emits a modality_shift moment when the consecutive-turn delta exceeds 0.3" do
      turns = [build_turn(turn_id: 1, avg_modality: 0.2), build_turn(turn_id: 2, avg_modality: 0.6)]

      result = engine.build_result(turns, source: no_op_source, label: "x", total: 2)

      moment = result.key_moments.find { |m| m.type == "modality_shift" }
      expect(moment.magnitude).to eq(0.4)
    end

    it "does not emit a modality_shift moment at or below the 0.3 threshold" do
      turns = [build_turn(turn_id: 1, avg_modality: 0.4), build_turn(turn_id: 2, avg_modality: 0.6)]

      result = engine.build_result(turns, source: no_op_source, label: "x", total: 2)

      expect(result.key_moments.map(&:type)).not_to include("modality_shift")
    end

    it "emits a deflation_anomaly when coherence < 0.35 and mood is interrogative/imperative" do
      turns = [
        build_turn(turn_id: 1, avg_tenor: 0.5, avg_modality: 0.5),
        build_turn(turn_id: 2, avg_tenor: 0.5, avg_modality: 0.5, dominant_mood: "interrogative",
          semantic_coherence_score: 0.2),
      ]

      result = engine.build_result(turns, source: no_op_source, label: "x", total: 2)

      expect(result.key_moments.map(&:type)).to eq(["deflation_anomaly"])
    end

    it "emits a deflation_anomaly when coherence < 0.35 and modality/tenor are low, even declarative" do
      turns = [
        build_turn(turn_id: 1, avg_tenor: 0.32, avg_modality: 0.5),
        build_turn(turn_id: 2, avg_tenor: 0.3, avg_modality: 0.5, dominant_mood: "declarative",
          semantic_coherence_score: 0.2),
      ]

      result = engine.build_result(turns, source: no_op_source, label: "x", total: 2)

      expect(result.key_moments.map(&:type)).to eq(["deflation_anomaly"])
    end

    it "emits a semantic_anomaly when coherence < 0.35 but the deflation condition is not met" do
      turns = [
        build_turn(turn_id: 1, avg_tenor: 0.55, avg_modality: 0.55),
        build_turn(turn_id: 2, avg_tenor: 0.6, avg_modality: 0.6, dominant_mood: "declarative",
          semantic_coherence_score: 0.2),
      ]

      result = engine.build_result(turns, source: no_op_source, label: "x", total: 2)

      expect(result.key_moments.map(&:type)).to eq(["semantic_anomaly"])
    end

    it "emits no anomaly moment when coherence is at or above 0.35, regardless of mood" do
      turns = [
        build_turn(turn_id: 1, avg_tenor: 0.5, avg_modality: 0.5),
        build_turn(turn_id: 2, avg_tenor: 0.3, avg_modality: 0.3, dominant_mood: "interrogative",
          semantic_coherence_score: 0.5),
      ]

      result = engine.build_result(turns, source: no_op_source, label: "x", total: 2)

      expect(result.key_moments.map(&:type)).not_to include("semantic_anomaly", "deflation_anomaly")
    end
  end

  describe "#build_result -> detect_example_passages" do
    it "picks the correct turn for each of the four passage_for calls out of 3+ turns" do
      turns = [
        build_turn(turn_id: 1, speaker: "A", avg_tenor: 0.3, avg_modality: 0.5, message_text: "T1"),
        build_turn(turn_id: 2, speaker: "B", avg_tenor: 0.9, avg_modality: 0.2, message_text: "T2"),
        build_turn(turn_id: 3, speaker: "C", avg_tenor: 0.1, avg_modality: 0.8, message_text: "T3"),
      ]

      result = engine.build_result(turns, source: no_op_source, label: "x", total: 3)
      passages = result.example_passages.to_h { |p| [p.label, p] }

      expect(passages["Most Formal"].text).to eq("T2")
      expect(passages["Most Casual"].text).to eq("T3")
      expect(passages["Most Certain"].text).to eq("T3")
      expect(passages["Most Hedged"].text).to eq("T2")
    end
  end

  describe "#build_result -> generate_insights" do
    it "returns [] when there are no turns" do
      result = engine.build_result([], source: no_op_source, label: "x", total: 0)

      expect(result.insights).to eq([])
    end

    it "includes a tenor-increase insight when the trend exceeds +0.1" do
      turns = [build_turn(turn_id: 1, avg_tenor: 0.2), build_turn(turn_id: 2, avg_tenor: 0.5)]

      result = engine.build_result(turns, source: no_op_source, label: "x", total: 2)

      expect(result.insights).to include(a_string_matching(/increased/))
    end

    it "includes a tenor-decrease insight when the trend is below -0.1" do
      turns = [build_turn(turn_id: 1, avg_tenor: 0.6), build_turn(turn_id: 2, avg_tenor: 0.2)]

      result = engine.build_result(turns, source: no_op_source, label: "x", total: 2)

      expect(result.insights).to include(a_string_matching(/decreased/))
    end

    it "omits a tenor-trend insight when the trend is within +/-0.1" do
      turns = [build_turn(turn_id: 1, avg_tenor: 0.3), build_turn(turn_id: 2, avg_tenor: 0.35)]

      result = engine.build_result(turns, source: no_op_source, label: "x", total: 2)

      expect(result.insights.grep(/formal|casual/)).to be_empty
    end

    it "omits speaker_share_insight for a single-speaker conversation" do
      turns = [build_turn(turn_id: 1, speaker: "Solo"), build_turn(turn_id: 2, speaker: "Solo")]

      result = engine.build_result(turns, source: no_op_source, label: "x", total: 2)

      expect(result.insights.grep(/contributed/)).to be_empty
    end

    it "reports the dominant speaker's share for a multi-speaker conversation" do
      turns = [
        build_turn(turn_id: 1, speaker: "Alice"),
        build_turn(turn_id: 2, speaker: "Alice"),
        build_turn(turn_id: 3, speaker: "Bob"),
]

      result = engine.build_result(turns, source: no_op_source, label: "x", total: 3)

      expect(result.insights).to include("Alice contributed 2 of 3 turns")
    end

    it "omits topic_insights entirely when topic_labels is nil" do
      turns = [build_turn(turn_id: 1)]

      result = engine.build_result(turns, source: no_op_source, label: "x", total: 1, topic_labels: nil)

      expect(result.insights.grep(/topics identified|prominent topic/)).to be_empty
    end

    it "includes topic count and dominant-topic insights when topic_labels is present" do
      turns = [build_turn(turn_id: 1, dominant_topic: 0), build_turn(turn_id: 2, dominant_topic: 0)]
      topic_labels = { 0 => %w[cats dogs pets], 1 => %w[stocks bonds] }

      result = engine.build_result(turns, source: no_op_source, label: "x", total: 2, topic_labels:)

      expect(result.insights).to include("2 topics identified across the conversation")
      expect(result.insights).to include(a_string_matching(/Most prominent topic: cats, dogs, pets \(2 turns\)/))
    end
  end

  describe "#analyze -> enqueue_review" do
    let(:review_queue_repo) { instance_double(SFL::Store::PgReviewQueueRepository) }
    let(:unit) { build_unit("doc-1") }

    before { allow(pipeline).to receive(:compile).and_return(Success([])) }

    it "never calls review_queue_repo when store: false" do
      allow(review_queue_repo).to receive(:enqueue)
      engine = described_class.new(pipeline:, review_queue_repo:)
      source = FakeAnalysisSource.new([unit], review_entries: {
        "doc-1" => {
          modality: "text",
          reason: "x",
          generated_text: "t",
          source_type: "s",
        },
      })

      engine.analyze(source, label: "x", store: false)

      expect(review_queue_repo).not_to have_received(:enqueue)
    end

    it "never calls review_queue_repo when store: true but source.review_entry returns nil" do
      allow(review_queue_repo).to receive(:enqueue)
      engine = described_class.new(pipeline:, review_queue_repo:)
      source = FakeAnalysisSource.new([unit], review_entries: {})

      engine.analyze(source, label: "x", store: true)

      expect(review_queue_repo).not_to have_received(:enqueue)
    end

    it "calls review_queue_repo.enqueue with document_id/source_file plus the merged entry when store: true" do
      allow(review_queue_repo).to receive(:enqueue)
      engine = described_class.new(pipeline:, review_queue_repo:)
      entry = { modality: "audio", reason: "audio_transcript", generated_text: "hello", source_type: "chat_native" }
      source = FakeAnalysisSource.new([unit], review_entries: { "doc-1" => entry })

      engine.analyze(source, label: "x", store: true)

      expect(review_queue_repo).to have_received(:enqueue).with(document_id: "doc-1", source_file: "doc-1", **entry)
    end
  end

  describe "#analyze -> fit_topics" do
    before { allow(pipeline).to receive(:compile).and_return(Success([])) }

    it "never instantiates a TopicModeler when topics: is nil" do
      factory = double("topic_modeler_factory") # rubocop:disable RSpec/VerifiedDoubles -- factory is a #call duck injected in place of a lambda
      allow(factory).to receive(:call)
      engine = described_class.new(pipeline:, topic_modeler_factory: factory)
      units = [build_unit("d1"), build_unit("d2"), build_unit("d3")]
      source = FakeAnalysisSource.new(units)

      engine.analyze(source, label: "x", topics: nil)

      expect(factory).not_to have_received(:call)
    end

    it "never instantiates a TopicModeler when units.size < 3, even with topics: set" do
      factory = double("topic_modeler_factory") # rubocop:disable RSpec/VerifiedDoubles
      allow(factory).to receive(:call)
      engine = described_class.new(pipeline:, topic_modeler_factory: factory)
      units = [build_unit("d1"), build_unit("d2")]
      source = FakeAnalysisSource.new(units)

      engine.analyze(source, label: "x", topics: 3)

      expect(factory).not_to have_received(:call)
    end

    it "calls the injected topic_modeler_factory with k: topics when topics: is set and units.size >= 3" do
      fake_modeler = double("topic_modeler", fit: nil, turns: [], topic_labels: { 0 => %w[a] }, # rubocop:disable RSpec/VerifiedDoubles -- TopicModeler stand-in shaped exactly like the real class's public surface fit_topics uses
        detect_topic_shifts: [])
      factory = double("topic_modeler_factory") # rubocop:disable RSpec/VerifiedDoubles
      allow(factory).to receive(:call).with(k: 3).and_return(fake_modeler)
      engine = described_class.new(pipeline:, topic_modeler_factory: factory)
      units = [build_unit("d1"), build_unit("d2"), build_unit("d3")]
      source = FakeAnalysisSource.new(units)

      engine.analyze(source, label: "x", topics: 3)

      expect(factory).to have_received(:call).with(k: 3)
      expect(fake_modeler).to have_received(:fit)
    end

    it "translates topics: 0 into k: nil (HDP mode)" do
      fake_modeler = double("topic_modeler", fit: nil, turns: [], topic_labels: {}, detect_topic_shifts: []) # rubocop:disable RSpec/VerifiedDoubles
      factory = double("topic_modeler_factory") # rubocop:disable RSpec/VerifiedDoubles
      allow(factory).to receive(:call).with(k: nil).and_return(fake_modeler)
      engine = described_class.new(pipeline:, topic_modeler_factory: factory)
      units = [build_unit("d1"), build_unit("d2"), build_unit("d3")]
      source = FakeAnalysisSource.new(units)

      engine.analyze(source, label: "x", topics: 0)

      expect(factory).to have_received(:call).with(k: nil)
    end
  end

  describe "#analyze -> report_progress" do
    it "reports a defaulted count of clauses whose annotation_source is untrusted" do
      trusted = build_annotated_clause(id: "c1", annotation_source: "llm")
      untrusted = build_annotated_clause(id: "c2", annotation_source: "stub")
      allow(pipeline).to receive(:compile).and_return(Success([trusted, untrusted]))
      progress_calls = []
      engine = described_class.new(pipeline:, on_progress: -> (**kwargs) { progress_calls << kwargs })
      source = FakeAnalysisSource.new([build_unit("d1")])

      engine.analyze(source, label: "x")

      expect(progress_calls.first[:defaulted]).to eq(1)
      expect(progress_calls.first[:clause_count]).to eq(2)
    end

    it "does nothing when on_progress is nil (no-op, does not raise)" do
      allow(pipeline).to receive(:compile).and_return(Success([]))
      engine = described_class.new(pipeline:)
      source = FakeAnalysisSource.new([build_unit("d1")])

      expect { engine.analyze(source, label: "x") }.not_to raise_error
    end
  end

  describe "#analyze -> stop_requested mid-loop interruption" do
    it "breaks compile_turns early and reports interrupted: true in metadata" do
      allow(pipeline).to receive(:compile).and_return(Success([]))
      calls = 0
      stop = lambda {
        calls += 1
        calls > 1
      }
      engine = described_class.new(pipeline:, stop_requested: stop)
      units = [build_unit("d1"), build_unit("d2"), build_unit("d3")]
      source = FakeAnalysisSource.new(units)

      result = engine.analyze(source, label: "x")

      expect(result.turns.size).to eq(1)
      expect(result.metadata[:interrupted]).to be(true)
    end
  end
end
