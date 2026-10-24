# frozen_string_literal: true

require "spec_helper"
require "pgvector"

RSpec.describe SFL::Store::PgGraphRepository do
  subject(:repository) { described_class.new(db:) }

  let(:db) { SFL::Store::StoreTestDb.db }

  before do
    SFL::Store::StoreTestDb.clean!
    %w[c-old c-new c-other].each do |id|
      db[:clauses].insert(external_id: id, text: id, section_id: "doc-1", sentence_index: 0, root_index: 0)
    end
    db[:embeddings].insert(clause_id: "c-old", embedding: Pgvector.encode(unit_vector), model: "embeddinggemma:latest")
    db[:embeddings].insert(clause_id: "c-new", embedding: Pgvector.encode(unit_vector), model: "embeddinggemma-2:440m")
    db[:embeddings].insert(clause_id: "c-other", embedding: Pgvector.encode(unit_vector), model: "other-model:latest")
  end

  def unit_vector = Array.new(768, 0.0).tap { |v| v[0] = 1.0 }

  def neighbour_ids(...)
    repository.semantic_neighbors("c-old", ...).map(&:to_id)
  end

  describe "#semantic_neighbors model filter (family:, model:)" do
    it "returns neighbours from every model when neither keyword is given (no filter)" do
      expect(neighbour_ids).to contain_exactly("c-new", "c-other")
    end

    it "keeps only neighbours whose stored model is in the family when family: is given" do
      expect(neighbour_ids(family: "embeddinggemma")).to eq(["c-new"])
    end

    it "keeps only neighbours with the exact stored model when model: is given" do
      db[:clauses].insert(external_id: "c-twin", text: "twin", section_id: "doc-1", sentence_index: 0, root_index: 0)
      db[:embeddings].insert(clause_id: "c-twin", embedding: Pgvector.encode(unit_vector), model: "embeddinggemma-2:440m")

      expect(repository.semantic_neighbors("c-new", model: "embeddinggemma-2:440m").map(&:to_id)).to eq(["c-twin"])
      expect(neighbour_ids(model: "embeddinggemma")).to eq([])
    end

    it "takes the seed from the selected models, so model: wins over family: when both are given" do
      # family: alone would seed from c-old; model: selects other-model:latest,
      # which has no embedding for c-old, so the seed is not found.
      expect(repository.semantic_neighbors("c-old", family: "embeddinggemma", model: "other-model:latest")).to eq([])
    end
  end
end
