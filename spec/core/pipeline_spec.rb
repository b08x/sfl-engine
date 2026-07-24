# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Pipeline do
  subject(:pipeline) { described_class.new(pass_one:, pass_two:, ideational_extractor:) }

  let(:syntactic_clause) do
    SFL::Core::Types::SyntacticClause.new(
      id: "c-1", text: "The committee approved the budget.",
      tokens: [], root_index: 0, sentence_index: 0, document_id: "doc-1"
    )
  end

  let(:ideational_payload) do
    SFL::Core::Types::IdeationalPayload.new(
      clause_id: "c-1", process_type: "material",
      participants: [], circumstances: [], raw_transitivity: {}
    )
  end

  let(:annotation_result) do
    SFL::Core::Types::AnnotationResult.new(
      interpersonal: SFL::Core::Types::InterpersonalPayload.new(
        clause_id: "c-1", mood: "declarative",
        modality_weight: 0.5, tenor: 0.5,
        speaker_attitude: nil, reasoning: nil, annotation_source: "llm"
      ),
      textual: nil
    )
  end

  let(:pass_one) { instance_double(SFL::Core::PassOne::Engine) }
  let(:ideational_extractor) { instance_double(SFL::Core::PassOne::IdeationalExtractor) }
  let(:pass_two) { instance_double(SFL::Core::Ports::Annotator) }

  before do
    allow(pass_one).to receive(:process).and_return([syntactic_clause])
    allow(ideational_extractor).to receive(:extract).with(syntactic_clause).and_return(ideational_payload)
    allow(pass_two).to receive(:annotate_batch).and_return([annotation_result])
  end

  describe "#compile" do
    it "returns Success with one AnnotatedClause per input clause on the happy path" do
      result = pipeline.compile("The committee approved the budget.", document_id: "doc-1")

      expect(result).to be_success
      annotated = result.value!
      expect(annotated.size).to eq(1)
      expect(annotated.first).to be_a(SFL::Core::Types::AnnotatedClause)
      expect(annotated.first.interpersonal.mood).to eq("declarative")
      expect(annotated.first.syntactic).to eq(syntactic_clause)
      expect(annotated.first.ideational).to eq(ideational_payload)
    end

    it "pairs each clause with its ideational extraction before annotating" do
      pipeline.compile("text", document_id: "doc-1")

      expect(pass_two).to have_received(:annotate_batch)
        .with([[syntactic_clause, ideational_payload]], context: anything)
    end

    context "when Pass 1 fails" do
      before do
        allow(pass_one).to receive(:process).and_raise(SFL::Core::PassOne::Error, "sidecar exploded")
      end

      it "returns a Failure tagged :pass_one_failed and never reaches Pass 2" do
        result = pipeline.compile("text", document_id: "doc-1")

        expect(result).to be_failure
        expect(result.failure).to eq([:pass_one_failed, "sidecar exploded"])
        expect(pass_two).not_to have_received(:annotate_batch)
      end
    end

    context "with storage" do
      subject(:pipeline) do
        described_class.new(pass_one:, pass_two:, ideational_extractor:, clause_store:)
      end

      let(:clause_store) { SFL::Core::Ports::Fake::ClauseStore.new }

      it "persists annotated clauses via ClauseStore when store: true and document_id given" do
        result = pipeline.compile("text", document_id: "doc-1", store: true, embed: false)

        expect(clause_store.find_by_document("doc-1")).to eq(result.value!)
      end

      it "does not persist when store: false" do
        pipeline.compile("text", document_id: "doc-1", store: false, embed: false)

        expect(clause_store.find_by_document("doc-1")).to eq([])
      end

      it "does not persist when document_id is nil" do
        pipeline.compile("text", document_id: nil, store: true, embed: false)

        expect(clause_store.find_by_document("doc-1")).to eq([])
      end
    end

    context "with embedding" do
      subject(:pipeline) do
        described_class.new(pass_one:, pass_two:, ideational_extractor:, embedding_store:, embedder:)
      end

      let(:embedding_store) { SFL::Core::Ports::Fake::EmbeddingStore.new }
      let(:embedder) { instance_double(SFL::Core::Ports::Embedder) }

      before do
        allow(embedder).to receive(:embed_batch).and_return([[0.1, 0.2]])
      end

      it "computes and persists embeddings via EmbeddingStore when embed: true and document_id given" do
        result = pipeline.compile("text", document_id: "doc-1", store: false, embed: true)
        annotated_id = result.value!.first.id

        expect(embedding_store.find_by_document("doc-1")).to eq({ annotated_id => [0.1, 0.2] })
      end

      it "does not embed when embed: false" do
        pipeline.compile("text", document_id: "doc-1", store: false, embed: false)

        expect(embedder).not_to have_received(:embed_batch)
      end

      it "does not embed when document_id is nil" do
        pipeline.compile("text", document_id: nil, store: false, embed: true)

        expect(embedder).not_to have_received(:embed_batch)
      end
    end

    context "with cache resume" do
      subject(:pipeline) do
        described_class.new(pass_one:, pass_two:, ideational_extractor:, cache:)
      end

      let(:cache) { SFL::Core::Ports::Fake::Cache.new }

      it "calls the annotator on the first resume: true run and writes results to cache" do
        result = pipeline.compile("text", document_id: "doc-1", store: false, embed: false, resume: true)

        expect(result).to be_success
        expect(pass_two).to have_received(:annotate_batch).once
      end

      it "serves the second resume: true run entirely from cache, without calling the annotator again" do
        first = pipeline.compile("text", document_id: "doc-1", store: false, embed: false, resume: true)
        second = pipeline.compile("text", document_id: "doc-1", store: false, embed: false, resume: true)

        expect(pass_two).to have_received(:annotate_batch).once
        expect(second.value!).to eq(first.value!)
      end

      it "reads each cache hit exactly once via #partition, never re-fetching to rebuild order" do
        pipeline.compile("text", document_id: "doc-1", store: false, embed: false, resume: true)

        allow(cache).to receive(:partition).and_call_original
        pipeline.compile("text", document_id: "doc-1", store: false, embed: false, resume: true)

        expect(cache).to have_received(:partition).once
      end
    end
  end
end
