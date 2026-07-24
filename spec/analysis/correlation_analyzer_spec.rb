# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::CorrelationAnalyzer do
  describe "#correlate_process_tenor" do
    it "returns an empty Hash when there are no clauses across any turn" do
      turns = [build_turn(clauses: [])]

      expect(described_class.new(turns).correlate_process_tenor).to eq({})
    end

    it "groups clauses across all turns by ideational process_type" do
      c1 = build_annotated_clause(id: "c1", process_type: "material", tenor: 0.4, modality: 0.6)
      c2 = build_annotated_clause(id: "c2", process_type: "mental", tenor: 0.8, modality: 0.2)
      c3 = build_annotated_clause(id: "c3", process_type: "material", tenor: 0.6, modality: 0.4)
      turns = [build_turn(turn_id: 1, clauses: [c1, c2]), build_turn(turn_id: 2, clauses: [c3])]

      result = described_class.new(turns).correlate_process_tenor

      expect(result.keys).to contain_exactly("material", "mental")
      expect(result["material"][:count]).to eq(2)
    end

    it "computes per-group avg_tenor/avg_modality as the mean of that group's clauses" do
      c1 = build_annotated_clause(id: "c1", process_type: "material", tenor: 0.2, modality: 0.4)
      c2 = build_annotated_clause(id: "c2", process_type: "material", tenor: 0.8, modality: 0.6)
      turns = [build_turn(clauses: [c1, c2])]

      result = described_class.new(turns).correlate_process_tenor

      expect(result["material"][:avg_tenor]).to eq(0.5)
      expect(result["material"][:avg_modality]).to eq(0.5)
    end
  end
end
