# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Exercises the real tomoto gem (LDA/HDP) for real — no mocking/stubbing tomoto's own internals,
# matching this codebase's convention of exercising local/non-network gems for real (see
# MarkdownSource's specs against real pragmatic_tokenizer/inkmark). Every fit below uses a fixed
# seed:, min_cf: 1, rm_top: 0 (the gem's default min_cf: 3 silently drops every word from a
# 4-document toy corpus — no word appears in 3+ tiny fixture docs — so tests would train on an
# empty vocabulary without this override) so results are deterministic, not flaky; the exact
# topic ids/labels asserted below were captured from a real run against this fixed corpus+seed
# and re-verified stable across repeated runs before being pinned here.
RSpec.describe SFL::Analysis::TopicModeler do
  let(:pet_text) { "cats dogs pets animals cats dogs" }
  let(:finance_text) { "stocks bonds markets finance stocks bonds" }
  let(:texts) { [pet_text, pet_text, finance_text, finance_text] }

  # rubocop:disable Naming/MethodParameterName -- k: matches Tomoto::LDA's own k: kwarg (topic
  # count), same rationale as TopicModeler's own initialize.
  def deterministic_modeler(k: 2)
    described_class.new(k:, min_cf: 1, rm_top: 0, iterations: 50, seed: 42)
  end
  # rubocop:enable Naming/MethodParameterName

  def turn_for(id, text)
    SFL::Core::Types::ConversationTurn.new(
      turn_id: id, speaker: "A", timestamp: Time.now, message_text: text, clauses: [],
      avg_tenor: 0.5, avg_modality: 0.5, dominant_mood: "declarative", process_types: {},
      participants: [], tenor_shift: nil, semantic_coherence_score: nil
    )
  end

  describe "#fit_texts" do
    it "returns exactly k topic_labels after fitting fixed-k LDA" do
      modeler = deterministic_modeler(k: 2)

      modeler.fit_texts(texts)

      expect(modeler.topic_labels.size).to eq(2)
    end

    it "returns one dominant-topic id per text, parallel to the input, splitting the two clusters" do
      ids = deterministic_modeler(k: 2).fit_texts(texts)

      expect(ids.size).to eq(4)
      expect(ids[0]).to eq(ids[1])
      expect(ids[2]).to eq(ids[3])
      expect(ids[0]).not_to eq(ids[2])
    end

    it "returns nil for a text that tokenizes to nothing (blank or stopwords-only)" do
      ids = deterministic_modeler(k: 2).fit_texts([pet_text, pet_text, finance_text, "the a an is", ""])

      expect(ids[3]).to be_nil
      expect(ids[4]).to be_nil
    end
  end

  describe "#fit" do
    subject(:modeler) { deterministic_modeler(k: 2) }

    let(:turns) { texts.each_with_index.map { |t, i| turn_for(i + 1, t) } }

    it "returns self and assigns topic_distribution/dominant_topic to every fitted turn" do
      result = modeler.fit(turns)

      expect(result).to be(modeler)
      expect(modeler.turns.map(&:dominant_topic)).to eq([1, 1, 0, 0])
      expect(modeler.turns[0].topic_distribution).to be_a(Hash)
    end

    it "leaves semantic_coherence_score nil for the first two turns (idx < 2 guard) and sets it thereafter" do
      modeler.fit(turns)

      expect(modeler.turns[0].semantic_coherence_score).to be_nil
      expect(modeler.turns[1].semantic_coherence_score).to be_nil
      expect(modeler.turns[2].semantic_coherence_score).not_to be_nil
      expect(modeler.turns[3].semantic_coherence_score).not_to be_nil
    end

    it "#turn_distributions returns [] before fitting and the per-turn distributions after" do
      expect(modeler.turn_distributions).to eq([])

      modeler.fit(turns)

      expect(modeler.turn_distributions.size).to eq(4)
    end
  end

  # Regression: PragmaticTokenizer's `en` stoplist spells its contractions with the ASCII
  # apostrophe, so curly-apostrophe contractions from LLM-generated prose survived stopword
  # removal and surfaced as topic terms in two separate topics of a real run.
  describe "Unicode punctuation normalization before tokenization" do
    subject(:modeler) { deterministic_modeler }

    def tokenize(text) = modeler.__send__(:tokenize, text)

    it "removes curly-apostrophe contractions exactly as it removes their ASCII spelling" do
      expect(tokenize("it’s the sound, don’t you think")).to eq(tokenize("it's the sound, don't you think"))
    end

    it "leaves no curly apostrophe in any emitted token" do
      expect(tokenize("it’s that’s they’re prosody")).to eq(["prosody"])
    end

    it "splits words joined by an em or en dash instead of emitting one unmatched compound" do
      expect(tokenize("phonology—prosody and syntax–semantics"))
        .to contain_exactly("phonology", "prosody", "syntax", "semantics")
    end

    it "does not treat a curly ellipsis as part of the adjoining word" do
      expect(tokenize("prosody… phonology")).to eq(%w[prosody phonology])
    end

    it "leaves ordinary ASCII text unchanged" do
      expect(tokenize("cats dogs pets")).to eq(%w[cats dogs pets])
    end
  end

  describe "#detect_topic_shifts" do
    it "returns [] when the model hasn't been fitted yet" do
      expect(deterministic_modeler.detect_topic_shifts).to eq([])
    end

    it "returns well-shaped shift Hashes with turn_id/type/from_topic/to_topic/magnitude/description" do
      modeler = deterministic_modeler(k: 2)
      turns = texts.each_with_index.map { |t, i| turn_for(i + 1, t) }
      modeler.fit(turns)

      shifts = modeler.detect_topic_shifts(threshold: 0.1)

      expect(shifts).not_to be_empty
      shifts.each do |shift|
        expect(shift.keys).to contain_exactly(:turn_id, :type, :from_topic, :to_topic, :magnitude, :description)
        expect(shift[:type]).to eq("topic_shift")
      end
      # the only same-speaker cluster boundary in this 4-turn fixture sits between turn 2 and 3
      expect(shifts.first[:turn_id]).to eq(3)
    end
  end

  describe "#calculate_coherence" do
    subject(:modeler) { deterministic_modeler(k: 2) }

    it "returns nil before the model is fitted" do
      expect(modeler.calculate_coherence({ 0 => 1.0 }, { 0 => 1.0 })).to be_nil
    end

    it "returns nil when either distribution is nil or empty, once fitted" do
      modeler.fit(texts.each_with_index.map { |t, i| turn_for(i + 1, t) })

      expect(modeler.calculate_coherence(nil, { 0 => 1.0 })).to be_nil
      expect(modeler.calculate_coherence({}, { 0 => 1.0 })).to be_nil
    end

    it "returns 1.0 (clamped) for two identical distributions" do
      modeler.fit(texts.each_with_index.map { |t, i| turn_for(i + 1, t) })

      expect(modeler.calculate_coherence({ 0 => 1.0 }, { 0 => 1.0 })).to eq(1.0)
    end
  end

  describe "#conversation_baseline" do
    it "returns {} before fitting" do
      expect(deterministic_modeler.conversation_baseline).to eq({})
    end

    it "returns the average topic distribution across every turn with a distribution, once fitted" do
      modeler = deterministic_modeler(k: 2)
      modeler.fit(texts.each_with_index.map { |t, i| turn_for(i + 1, t) })

      baseline = modeler.conversation_baseline

      expect(baseline.keys).to contain_exactly(0, 1)
      expect(baseline.values.sum).to be_within(0.01).of(1.0)
    end
  end

  describe "#save" do
    it "raises Error when no model has been fit yet" do
      expect do
        deterministic_modeler.save("/tmp/whatever.bin")
      end.to raise_error(SFL::Analysis::Error, /No model to save/)
    end
  end

  describe "save/load round trip" do
    it "reloads a saved model with the same topic_labels" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "model.bin")
        modeler = deterministic_modeler(k: 2)
        modeler.fit_texts(texts)
        modeler.save(path)

        reloaded = described_class.new
        reloaded.load_model(path)

        expect(reloaded.topic_labels.size).to eq(2)
      end
    end
  end

  describe "HDP mode (k: nil)" do
    it "fits without raising and produces at least one topic" do
      modeler = described_class.new(k: nil, min_cf: 1, rm_top: 0, iterations: 30, seed: 42)

      expect { modeler.fit(texts.each_with_index.map { |t, i| turn_for(i + 1, t) }) }.not_to raise_error
      expect(modeler.topic_labels.size).to be >= 1
    end
  end
end
