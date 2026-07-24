# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe SFL::LLM::Engine do
  let(:token) do
    SFL::Core::Types::SyntacticToken.new(
      text: "works", lemma: "work", pos: "VERB", tag: "VBZ",
      dep: "ROOT", head_index: -1, morphology: {}, index: 0
    )
  end
  let(:clause) do
    SFL::Core::Types::SyntacticClause.new(
      id: "c-1", text: "It works.", tokens: [token], root_index: 0, sentence_index: 0, document_id: "doc-1"
    )
  end
  let(:ideational) do
    SFL::Core::Types::IdeationalPayload.new(
      clause_id: "c-1", process_type: "material",
      participants: [SFL::Core::Types::Participant.new(role: "Actor", text: "It")],
      circumstances: [], raw_transitivity: {}
    )
  end

  let(:valid_raw) do
    {
      mood: "declarative",
      modality_weight: 0.8,
      tenor: 0.6,
      speaker_attitude: "neutral",
      topical_theme: "It",
      textual_theme: nil,
      interpersonal_theme: nil,
      rheme: "works",
      theme_type: "unmarked",
      reasoning: "because",
      inference_rule: "default_declarative",
      confidence: 0.9,
      premises: [{ type: "pos", source: "works", value: "VERB", weight: 0.5 }],
    }
  end

  describe "#initialize" do
    it "raises ArgumentError when given neither chat: nor explicit annotators" do
      expect { described_class.new }.to raise_error(ArgumentError, /chat:/)
    end
  end

  describe "#annotate" do
    it "builds a full AnnotationResult with annotation_source llm and a derivation_hash on success" do
      clause_annotator = instance_double(SFL::LLM::Annotators::ClauseAnnotator, call: valid_raw)
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double)

      result = engine.annotate(clause, ideational)

      expect(result.interpersonal.annotation_source).to eq("llm")
      expect(result.interpersonal.mood).to eq("declarative")
      expect(result.interpersonal.reasoning_trace.derivation_hash).to match(/\A[0-9a-f]{64}\z/)
      expect(result.textual.topical_theme).to eq("It")
    end

    it "passes a structured context Hash (not a formatted string) to the annotator" do
      clause_annotator = instance_double(SFL::LLM::Annotators::ClauseAnnotator)
      allow(clause_annotator).to receive(:call).and_return(valid_raw)
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double)

      engine.annotate(clause, ideational)

      expect(clause_annotator).to have_received(:call) do |context|
        expect(context).to include(text: "It works.", process_type: "material")
        expect(context[:root_verb]).to include("works")
      end
    end

    it "degrades to a truthful fallback when a value violates its Dry::Struct contract (F6/D9)" do
      clause_annotator = instance_double(
        SFL::LLM::Annotators::ClauseAnnotator, call: valid_raw.merge(modality_weight: 5.0)
      )
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double)

      result = engine.annotate(clause, ideational)

      expect(result.interpersonal.annotation_source).to eq("fallback")
      expect(result.interpersonal.modality_weight).to eq(0.5)
    end

    it "resolves a fuzzy/aliased mood via ClassificationRegistry rather than rejecting it" do
      clause_annotator = instance_double(SFL::LLM::Annotators::ClauseAnnotator, call: valid_raw.merge(mood: "question"))
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double)

      result = engine.annotate(clause, ideational)

      expect(result.interpersonal.annotation_source).to eq("llm")
      expect(result.interpersonal.mood).to eq("interrogative")
    end

    it "leaves interpersonal values intact when only the reasoning_trace's premises are malformed" do
      bad_premise_raw = valid_raw.merge(premises: [{ type: "pos", source: "x" }]) # missing required :value
      clause_annotator = instance_double(SFL::LLM::Annotators::ClauseAnnotator, call: bad_premise_raw)
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double)

      result = engine.annotate(clause, ideational)

      expect(result.interpersonal.annotation_source).to eq("llm")
      expect(result.interpersonal.mood).to eq("declarative")
      expect(result.interpersonal.reasoning_trace).to be_nil
    end

    it "degrades to a truthful fallback when the annotator raises" do
      clause_annotator = instance_double(SFL::LLM::Annotators::ClauseAnnotator)
      allow(clause_annotator).to receive(:call).and_raise(StandardError, "network blew up")
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double)

      result = engine.annotate(clause, ideational)

      expect(result.interpersonal.annotation_source).to eq("fallback")
      expect(result.interpersonal.reasoning).to include("network blew up")
    end

    it "wraps the call in the injected Breaker" do
      clause_annotator = instance_double(SFL::LLM::Annotators::ClauseAnnotator, call: valid_raw)
      breaker = instance_double(SFL::Core::Ports::TimeoutBreaker)
      allow(breaker).to receive(:call).and_yield
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double, breaker:)

      engine.annotate(clause, ideational)

      expect(breaker).to have_received(:call).with("pass_two.annotate")
    end
  end

  describe "#annotate_batch" do
    it "returns [] for an empty pairs list without calling the batch annotator" do
      batch_clause_annotator = instance_double(SFL::LLM::Annotators::BatchClauseAnnotator)
      allow(batch_clause_annotator).to receive(:call)
      engine = described_class.new(clause_annotator: double, batch_clause_annotator:)

      expect(engine.annotate_batch([])).to eq([])
      expect(batch_clause_annotator).not_to have_received(:call)
    end

    it "maps each raw annotation back to its clause by index, in input order" do
      clause2 = clause.new(id: "c-2", text: "It fails.")
      raw_results = [valid_raw.merge(index: 1, mood: "imperative"), valid_raw.merge(index: 0)]
      batch_clause_annotator = instance_double(SFL::LLM::Annotators::BatchClauseAnnotator, call: raw_results)
      engine = described_class.new(clause_annotator: double, batch_clause_annotator:)

      results = engine.annotate_batch([[clause, ideational], [clause2, ideational]])

      expect(results[0].interpersonal.mood).to eq("declarative")
      expect(results[1].interpersonal.mood).to eq("imperative")
    end

    it "defaults any clause the LLM didn't return an annotation for" do
      clause2 = clause.new(id: "c-2", text: "Missing.")
      batch_clause_annotator = instance_double(
        SFL::LLM::Annotators::BatchClauseAnnotator, call: [valid_raw.merge(index: 0)]
      )
      engine = described_class.new(clause_annotator: double, batch_clause_annotator:)

      results = engine.annotate_batch([[clause, ideational], [clause2, ideational]])

      expect(results[0].interpersonal.annotation_source).to eq("llm")
      expect(results[1].interpersonal.annotation_source).to eq("fallback")
    end

    it "defaults every clause when the batch call itself raises" do
      batch_clause_annotator = instance_double(SFL::LLM::Annotators::BatchClauseAnnotator)
      allow(batch_clause_annotator).to receive(:call).and_raise(StandardError, "boom")
      engine = described_class.new(clause_annotator: double, batch_clause_annotator:)

      results = engine.annotate_batch([[clause, ideational]])

      expect(results).to all(have_attributes(interpersonal: have_attributes(annotation_source: "fallback")))
    end
  end

  describe "logging" do
    let(:io) { StringIO.new }
    let(:logger) { SFL::Core::Ports::StandardLogger.new(io:, level: Logger::DEBUG) }

    it "logs debug on start and info with mood/tenor/latency on completion" do
      clause_annotator = instance_double(SFL::LLM::Annotators::ClauseAnnotator, call: valid_raw)
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double, logger:)

      engine.annotate(clause, ideational)

      expect(io.string).to include("pass_two started")
      expect(io.string).to include("pass_two completed")
      expect(io.string).to include("mood=declarative")
    end

    it "logs a warning when a value is rejected by its contract" do
      clause_annotator = instance_double(
        SFL::LLM::Annotators::ClauseAnnotator, call: valid_raw.merge(modality_weight: 5.0)
      )
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double, logger:)

      engine.annotate(clause, ideational)

      expect(io.string).to include("invalid interpersonal")
    end

    it "logs a warning when the mood value is an unrecognized schema gap" do
      clause_annotator = instance_double(
        SFL::LLM::Annotators::ClauseAnnotator, call: valid_raw.merge(mood: "totally_unrelated_garbage")
      )
      engine = described_class.new(clause_annotator:, batch_clause_annotator: double, logger:)

      engine.annotate(clause, ideational)

      expect(io.string).to include("unknown mood")
    end
  end
end
