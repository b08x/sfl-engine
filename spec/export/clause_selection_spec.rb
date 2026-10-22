# frozen_string_literal: true

require_relative "export_helper"

# Fact 41: no duplicates, document and section order.
RSpec.describe SFL::Export::ClauseSelection do
  it "orders clauses by document and section ordinal whatever order the picks arrive in" do
    records = ExportSpecSupport.records(ExportSpecSupport.papers_picks.reverse)

    expect(records.map(&:id)).to eq(%w[i1 i2 b1 m1 t1 t2])
  end

  it "exports each clause once" do
    picks = ExportSpecSupport.papers_picks
    records = ExportSpecSupport.records(picks + [picks.first.with(clause_ids: ["i2"])])

    expect(records.map(&:id)).to eq(%w[i1 i2 b1 m1 t1 t2])
  end

  it "keeps only the chosen clauses of a partly selected section" do
    pick = ExportSpecSupport.papers_picks.first.with(clause_ids: ["i2"])

    expect(ExportSpecSupport.records([pick]).map(&:id)).to eq(["i2"])
  end

  it "builds each record from its pick and the stored clause, defaulting missing metafunctions to empty hashes" do
    pick = ExportSpecSupport.papers_picks.first.with(section_id: "x#1", clause_ids: nil)
    source = SFL::Core::Ports::Fake::BrowseSource.new(clauses: {
      "x#1" => [
        { id: "c1", text: "One.", ideational: { process_type: "material" }, interpersonal: { mood: "declarative" } },
        { id: "c2", text: "Two." },
      ],
    })
    records = described_class.new(source:).resolve([pick])

    expect(records).to eq([
      SFL::Export::ClauseRecord.new(pick:, id: "c1", text: "One.", ideational: { process_type: "material" },
        interpersonal: { mood: "declarative" }),
      SFL::Export::ClauseRecord.new(pick:, id: "c2", text: "Two.", ideational: {}, interpersonal: {}),
    ])
  end
end
