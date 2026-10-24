# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe SFL::Core::Pipeline do
  subject(:pipeline) { described_class.new(pass_one:, pass_two:, ideational_extractor:) }

  def build_zero_word_clause
    SFL::Core::Types::SyntacticClause.new(
      id: "c-zero", text: "...", tokens: [], root_index: 0, sentence_index: 0, section_id: "doc-1"
    )
  end

  def build_zero_word_ideational
    SFL::Core::Types::IdeationalPayload.new(
      clause_id: "c-zero", process_type: "material", participants: [], circumstances: [], raw_transitivity: {}
    )
  end

  let(:syntactic_clause) do
    SFL::Core::Types::SyntacticClause.new(
      id: "c-1", text: "The committee approved the budget.",
      tokens: [], root_index: 0, sentence_index: 0, section_id: "doc-1"
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
      result = pipeline.compile("The committee approved the budget.", section_id: "doc-1")

      expect(result).to be_success
      annotated = result.value!
      expect(annotated.size).to eq(1)
      expect(annotated.first).to be_a(SFL::Core::Types::AnnotatedClause)
      expect(annotated.first.interpersonal.mood).to eq("declarative")
      # Pipeline scores readability on every clause (Analysis::ReadabilityScorer,
      # real by default), so the syntactic clause it returns differs from the
      # input fixture only in that one attribute.
      expect(annotated.first.syntactic.to_h.except(:readability))
        .to eq(syntactic_clause.to_h.except(:readability))
      expect(annotated.first.syntactic.readability).to be_a(SFL::Core::Types::Readability)
      expect(annotated.first.ideational).to eq(ideational_payload)
    end

    it "pairs each clause with its ideational extraction before annotating" do
      pipeline.compile("text", section_id: "doc-1")

      expect(pass_two).to have_received(:annotate_batch)
        .with([[syntactic_clause, ideational_payload]], context: anything)
    end

    context "when Pass 1 fails" do
      before do
        allow(pass_one).to receive(:process).and_raise(SFL::Core::PassOne::Error, "sidecar exploded")
      end

      it "returns a Failure tagged :pass_one_failed and never reaches Pass 2" do
        result = pipeline.compile("text", section_id: "doc-1")

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

      it "persists annotated clauses via ClauseStore when store: true and section_id given" do
        result = pipeline.compile("text", section_id: "doc-1", store: true, embed: false)

        expect(clause_store.find_by_section("doc-1")).to eq(result.value!)
      end

      it "does not persist when store: false" do
        pipeline.compile("text", section_id: "doc-1", store: false, embed: false)

        expect(clause_store.find_by_section("doc-1")).to eq([])
      end

      it "does not persist when section_id is nil" do
        pipeline.compile("text", section_id: nil, store: true, embed: false)

        expect(clause_store.find_by_section("doc-1")).to eq([])
      end
    end

    context "with a section registry" do
      subject(:pipeline) do
        described_class.new(pass_one:, pass_two:, ideational_extractor:, clause_store:, section_registry:)
      end

      let(:clause_store) { SFL::Core::Ports::Fake::ClauseStore.new }
      let(:section_registry) { SFL::Core::Ports::Fake::SectionRegistry.new(collection: "papers") }
      let(:unit) { SFL::Core::Types::Unit.new(section_id: "doc-1", text: "text", document_key: "/p/doc.md") }

      it "registers the unit's document and section with its clause count after storing the clauses" do
        pipeline.compile("text", section_id: "doc-1", unit:, store: true, embed: false)

        expect(section_registry.documents["/p/doc.md"]).to include(collection: "papers", section_count: 1)
        expect(section_registry.sections["doc-1"]).to include(clause_count: 1, ordinal: 1)
      end

      it "stores the clauses and registers the section inside one registry transaction" do
        events = []
        allow(section_registry).to receive(:transaction).and_wrap_original do |original, &block|
          events << :begin
          original.call(&block).tap { events << :commit }
        end
        allow(clause_store).to(receive(:replace_section).and_wrap_original { |m, *args| (events << :clauses) && m.call(*args) })
        allow(section_registry).to(receive(:register).and_wrap_original { |m, *args| (events << :section) && m.call(*args) })

        pipeline.compile("text", section_id: "doc-1", unit:, store: true, embed: false)

        expect(events).to eq(%i[begin clauses section commit])
      end

      it "registers nothing when store: false or no unit is given" do
        pipeline.compile("text", section_id: "doc-1", unit:, store: false, embed: false)
        pipeline.compile("text", section_id: "doc-1", store: true, embed: false)

        expect(section_registry.sections).to be_empty
        expect(clause_store.find_by_section("doc-1").size).to eq(1)
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

      it "computes and persists embeddings via EmbeddingStore when embed: true and section_id given" do
        result = pipeline.compile("text", section_id: "doc-1", store: false, embed: true)
        annotated_id = result.value!.first.id

        expect(embedding_store.find_by_section("doc-1")).to eq({ annotated_id => [0.1, 0.2] })
      end

      it "does not embed when embed: false" do
        pipeline.compile("text", section_id: "doc-1", store: false, embed: false)

        expect(embedder).not_to have_received(:embed_batch)
      end

      it "does not embed when section_id is nil" do
        pipeline.compile("text", section_id: nil, store: false, embed: true)

        expect(embedder).not_to have_received(:embed_batch)
      end
    end

    context "with pass_one_only" do
      it "stubs interpersonal/textual payloads and never calls the annotator" do
        result = pipeline.compile("text", section_id: "doc-1", store: false, embed: false, pass_one_only: true)

        expect(result).to be_success
        annotated = result.value!.first
        expect(annotated.interpersonal.mood).to eq("declarative")
        expect(annotated.interpersonal.modality_weight).to eq(0.5)
        expect(annotated.interpersonal.tenor).to eq(0.5)
        expect(annotated.interpersonal.annotation_source).to eq("stub")
        expect(annotated.textual.topical_theme).to be_nil
        expect(pass_two).not_to have_received(:annotate_batch)
      end

      it "ignores resume: true — no cache lookup for stubbed annotations" do
        cached_pipeline = described_class.new(
          pass_one:, pass_two:, ideational_extractor:, cache: SFL::Core::Ports::Fake::Cache.new
        )

        result = cached_pipeline.compile("text", section_id: "doc-1", resume: true, pass_one_only: true, store: false,
          embed: false)

        expect(result.value!.first.interpersonal.annotation_source).to eq("stub")
        expect(pass_two).not_to have_received(:annotate_batch)
      end
    end

    context "with cache resume" do
      subject(:pipeline) do
        described_class.new(pass_one:, pass_two:, ideational_extractor:, cache:)
      end

      let(:cache) { SFL::Core::Ports::Fake::Cache.new }

      it "calls the annotator on the first resume: true run and writes results to cache" do
        result = pipeline.compile("text", section_id: "doc-1", store: false, embed: false, resume: true)

        expect(result).to be_success
        expect(pass_two).to have_received(:annotate_batch).once
      end

      it "serves the second resume: true run entirely from cache, without calling the annotator again" do
        first = pipeline.compile("text", section_id: "doc-1", store: false, embed: false, resume: true)
        second = pipeline.compile("text", section_id: "doc-1", store: false, embed: false, resume: true)

        expect(pass_two).to have_received(:annotate_batch).once
        expect(second.value!).to eq(first.value!)
      end

      it "reads each cache hit exactly once via #partition, never re-fetching to rebuild order" do
        pipeline.compile("text", section_id: "doc-1", store: false, embed: false, resume: true)

        allow(cache).to receive(:partition).and_call_original
        pipeline.compile("text", section_id: "doc-1", store: false, embed: false, resume: true)

        expect(cache).to have_received(:partition).once
      end
    end

    # Regression for the JSON::GeneratorError "NaN not allowed in JSON" crash:
    # a zero-word clause (code fence, emoji, bare punctuation — common in a
    # Claude Code export) makes Lingua::EN::Readability return NaN (0.0/0),
    # which reached FileCache#write's JSON.generate via this exact path.
    context "with a zero-word clause on a real FileCache" do
      subject(:file_cache_pipeline) do
        described_class.new(pass_one:, pass_two:, ideational_extractor:,
          cache: SFL::Core::Ports::FileCache.new(cache_dir:))
      end

      let(:cache_dir) { Dir.mktmpdir }
      let(:zero_word_clause) { build_zero_word_clause }
      let(:zero_word_ideational) { build_zero_word_ideational }

      before do
        allow(pass_one).to receive(:process).and_return([zero_word_clause])
        allow(ideational_extractor).to receive(:extract).with(zero_word_clause)
          .and_return(zero_word_ideational)
      end

      after { FileUtils.remove_entry(cache_dir) }

      it "caches the clause without NaN reaching FileCache#write" do
        result = file_cache_pipeline.compile("...", section_id: "doc-1", store: false, embed: false,
          resume: true)

        expect(result).to be_success
        readability = result.value!.first.syntactic.readability
        expect(readability.flesch).to be_nil
        expect(readability.kincaid).to be_nil
        expect(readability.fog).to be_nil

        # The written entry must survive a --resume hit: the second compile
        # is served from cache, so the annotator ran exactly once overall.
        file_cache_pipeline.compile("...", section_id: "doc-1", store: false, embed: false, resume: true)

        expect(pass_two).to have_received(:annotate_batch).once
      end
    end
  end
end
