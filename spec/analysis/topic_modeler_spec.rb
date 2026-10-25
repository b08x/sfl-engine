# frozen_string_literal: true

require "spec_helper"

# Records every fit call and returns the scripted results in order. Stands in
# for SFL::Analysis::BertopicSidecar, so nothing spawns Python.
class FakeTopicSidecar
  attr_reader :calls

  def initialize(*results)
    @results = results
    @calls = []
  end

  def fit(**kwargs)
    @calls << kwargs
    raise "no scripted sidecar result left" if @results.empty?

    @results.shift
  end
end

# Returns a fixed probe vector, or raises the probe error, and records each batch. Stands in for a
# Core::Ports::Embedder, so nothing calls Ollama.
class FakeTopicEmbedder
  include SFL::Core::Ports::Embedder

  attr_reader :batches

  def initialize(probe: [0.1, 0.2])
    @probe = probe
    @batches = []
  end

  def embed(_text)
    raise @probe if @probe.is_a?(Exception)

    @probe
  end

  def embed_batch(texts)
    @batches << texts
    texts.map { |text| [text.length.to_f, 1.0] }
  end
end

RSpec.describe SFL::Analysis::TopicModeler do
  let(:sidecar_command) { ["bertopic-sidecar"] }
  let(:embedder) { FakeTopicEmbedder.new }
  let(:embedder_info) { { provider: "ollama", model: "embeddinggemma:latest", endpoint: "http://localhost:11434" } }
  # 40 turns: 12 in eight topics (coverage exactly 0.30), 28 outliers.
  let(:gate_edge_topics) { Array.new(12) { |i| i % 8 } + Array.new(28, -1) }

  def turns_for(count)
    Array.new(count) { |i| turn_with("turn #{i + 1}", i + 1) }
  end

  def turn_with(text, turn_id)
    SFL::Core::Types::ConversationTurn.new(
      turn_id:, speaker: "A", timestamp: Time.now, message_text: text, clauses: [],
      avg_tenor: 0.5, avg_modality: 0.5, dominant_mood: "declarative", process_types: {},
      participants: [], tenor_shift: nil, semantic_coherence_score: nil
    )
  end

  # Builds a sidecar result whose coverage is computed from the topics, as the real client does.
  def sidecar_result(topics, words: nil)
    topic_words = words || topics.reject { |t| t == -1 }.uniq.to_h { |t| [t, ["word#{t}"]] }
    { topics:, topic_words:, coverage: topics.count { |t| t != -1 }.fdiv(topics.size) }
  end

  def modeler(sidecar:, store: nil, speaker_names: [], embedder: self.embedder, **extra)
    described_class.new(
      embedder:, sidecar_command:, sidecar:, store:, speaker_names:, embedder_info:,
      collection_key: "conv", document_key: "doc-1", run_id: "run-1", **extra
    )
  end

  describe "public surface" do
    it "keeps the methods the engine calls and drops save and load_model" do
      topic_modeler = modeler(sidecar: FakeTopicSidecar.new)

      expect(topic_modeler).to respond_to(:fit, :turn_distributions, :detect_topic_shifts, :calculate_coherence, :conversation_baseline)
      expect(topic_modeler).not_to respond_to(:save)
      expect(topic_modeler).not_to respond_to(:load_model)
    end
  end

  describe "one-hot topic distributions" do
    let(:sidecar) { FakeTopicSidecar.new(sidecar_result([0, 0, 1, -1], words: { 0 => %w[cats dogs], 1 => %w[stocks] })) }

    it "gives each turn a one-hot distribution over its topic and an empty one for outliers" do
      topic_modeler = modeler(sidecar:)
      topic_modeler.fit(turns_for(4))

      expect(topic_modeler.turn_distributions).to eq([{ 0 => 1.0 }, { 0 => 1.0 }, { 1 => 1.0 }, {}])
    end

    it "gives outlier turns a nil coherence score" do
      topic_modeler = modeler(sidecar:)
      topic_modeler.fit(turns_for(4))

      expect(topic_modeler.turns.last.semantic_coherence_score).to be_nil
    end

    it "sets the conversation baseline to the mean of the one-hot vectors" do
      topic_modeler = modeler(sidecar:)
      topic_modeler.fit(turns_for(4))

      expect(topic_modeler.conversation_baseline).to eq({ 0 => 0.6667, 1 => 0.3333 })
    end

    it "exposes the sidecar's topic words as topic_labels" do
      topic_modeler = modeler(sidecar:)
      topic_modeler.fit(turns_for(4))

      expect(topic_modeler.topic_labels).to eq({ 0 => %w[cats dogs], 1 => %w[stocks] })
    end
  end

  describe "coverage gate" do
    it "passes on the first attempt at coverage 0.5" do
      sidecar = FakeTopicSidecar.new(sidecar_result([0, 0, -1, -1]))
      result = modeler(sidecar:).fit(turns_for(4))

      expect(result).to include(coverage: 0.5, attempts: 1)
      expect(sidecar.calls.size).to eq(1)
    end

    it "treats coverage exactly 0.30 as a failure and retries with reduced nr_topics and min_topic_size" do
      retry_topics = Array.new(20) { |i| i % 4 } + Array.new(20, -1)
      sidecar = FakeTopicSidecar.new(sidecar_result(gate_edge_topics), sidecar_result(retry_topics))

      result = modeler(sidecar:).fit(turns_for(40))

      expect(result).to include(attempts: 2, coverage: 0.5)
      expect(sidecar.calls.first).to include(k: nil, min_topic_size: 4)
      expect(sidecar.calls.last).to include(k: 4, min_topic_size: 2)
    end

    it "uses nr_topics 2 on the retry when the first attempt found no topics" do
      sidecar = FakeTopicSidecar.new(sidecar_result(Array.new(10, -1)), sidecar_result([0, 0, 0, 0, 0, 0, 0, 0, 0, -1]))

      result = modeler(sidecar:).fit(turns_for(10))

      expect(result).to include(attempts: 2)
      expect(sidecar.calls.last).to include(k: 2, min_topic_size: 2)
    end

    it "raises TopicCoverageError naming both coverages and topic counts when both attempts miss the gate" do
      retry_topics = Array.new(10) { |i| i % 4 } + Array.new(30, -1)
      sidecar = FakeTopicSidecar.new(sidecar_result(gate_edge_topics), sidecar_result(retry_topics))
      store = instance_spy(SFL::Store::PgTopicModelStore)

      expect { modeler(sidecar:, store:).fit(turns_for(40)) }
        .to raise_error(SFL::Analysis::TopicCoverageError, /attempt 1 coverage 0\.3 with 8 topics.*attempt 2 coverage 0\.25 with 4 topics/)
      expect(store).not_to have_received(:save)
    end
  end

  describe "embedder probe" do
    it "raises an Analysis::Error naming provider, model and endpoint when the probe raises, without calling the sidecar" do
      failing = FakeTopicEmbedder.new(probe: RuntimeError.new("connection refused"))
      sidecar = FakeTopicSidecar.new(sidecar_result([0, 0, -1, -1]))

      expect { modeler(sidecar:, embedder: failing).fit(turns_for(4)) }
        .to raise_error(SFL::Analysis::Error, %r{provider: ollama.*model: embeddinggemma:latest.*endpoint: http://localhost:11434})
      expect(sidecar.calls).to be_empty
    end

    it "raises the same way when the probe returns an empty vector" do
      empty = FakeTopicEmbedder.new(probe: [])
      sidecar = FakeTopicSidecar.new(sidecar_result([0, 0, -1, -1]))

      expect { modeler(sidecar:, embedder: empty).fit(turns_for(4)) }
        .to raise_error(SFL::Analysis::Error, /provider: ollama.*probe returned an empty vector/)
      expect(sidecar.calls).to be_empty
    end
  end

  describe "input cleaning" do
    it "applies TopicInputCleaner to the texts sent to both the embedder and the sidecar" do
      raw = ["Alice: hello there", "[Alice] Hi   again", "You are a helpful assistant", "last turn"]
      turns = raw.each_with_index.map { |text, i| turn_with(text, i + 1) }
      sidecar = FakeTopicSidecar.new(sidecar_result([0, 0, -1, -1]))

      modeler(sidecar:, speaker_names: ["Alice"]).fit(turns)

      expected = ["hello there", "Hi again", "", "last turn"]
      expect(embedder.batches).to eq([expected])
      expect(sidecar.calls.first[:texts]).to eq(expected)
    end
  end

  describe "store" do
    let(:sidecar) { FakeTopicSidecar.new(sidecar_result([0, 0, -1, -1])) }

    it "saves the result once when a store is injected" do
      store = instance_spy(SFL::Store::PgTopicModelStore)

      modeler(sidecar:, store:).fit(turns_for(4))

      expect(store).to have_received(:save).once.with(
        collection_key: "conv", document_key: "doc-1", run_id: "run-1",
        result: { topics: [0, 0, -1, -1], topic_words: { 0 => ["word0"] }, coverage: 0.5, attempts: 1 }
      )
    end

    it "returns the result without persisting when no store is injected" do
      result = modeler(sidecar:).fit(turns_for(4))

      expect(result).to include(attempts: 1)
    end

    it "refuses a store without the collection and document keys" do
      store = instance_spy(SFL::Store::PgTopicModelStore)

      expect { described_class.new(embedder:, sidecar_command:, sidecar:, store:) }
        .to raise_error(SFL::Analysis::Error, /collection_key and document_key/)
    end
  end
end
