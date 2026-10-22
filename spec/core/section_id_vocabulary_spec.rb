# frozen_string_literal: true

require "spec_helper"

# Facts 2 and 3 (M0): the per-segment identifier is `section_id` on the six
# types, the ports, the stores and the pipeline. The negative checks match
# /document/ so any leftover pre-rename name fails them. The one allowed
# match is Unit#document_key, which names the whole document (fact 3).
RSpec.describe "section_id vocabulary" do # rubocop:disable RSpec/DescribeClass -- a cross-cutting naming contract
  types = %w[Unit AnnotatedClause GraphNode RetrievalResult SyntacticClause SyntacticSentence]

  types.each do |name|
    it "gives #{name} a section_id attribute and no document attribute" do
      keys = SFL::Core::Types.const_get(name).schema.keys.map(&:name)

      expect(keys).to include(:section_id)
      expect(keys.grep(/document/) - [:document_key]).to be_empty
    end
  end

  it "gives Unit a document_key and an optional parent_section_id (fact 3)" do
    unit = SFL::Core::Types::Unit.new(section_id: "a.md#intro", text: "t")

    expect(unit).to have_attributes(document_key: nil, parent_section_id: nil)
    expect(unit.new(document_key: "a.md", parent_section_id: "a.md#top").document_key).to eq("a.md")
  end

  {
    SFL::Core::Ports::ClauseStore => %i[replace_section find_by_section],
    SFL::Core::Ports::EmbeddingStore => %i[replace_section],
    SFL::Store::PgClauseStore => %i[replace_section find_by_section],
    SFL::Store::PgEmbeddingStore => %i[replace_section],
    SFL::Core::Ports::Fake::ClauseStore => %i[replace_section find_by_section],
    SFL::Core::Ports::Null::ClauseStore => %i[replace_section find_by_section],
  }.each do |owner, methods|
    it "names #{owner}'s per-section methods #{methods.join(', ')}" do
      names = owner.instance_methods

      expect(names).to include(*methods)
      expect(names.grep(/document/)).to be_empty
    end
  end

  it "takes section_id as Pipeline#compile's keyword" do
    keywords = SFL::Core::Pipeline.instance_method(:compile).parameters.map(&:last)

    expect(keywords).to include(:section_id)
    expect(keywords.grep(/document/)).to be_empty
  end
end
