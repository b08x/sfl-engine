# frozen_string_literal: true

require "spec_helper"

# Fact 13 and the plan's heading-tree edge cases.
RSpec.describe SFL::Core::Loaders::HeadingTree do
  def unit(id, level) = SFL::Core::Types::Unit.new(section_id: id, text: "t", metadata: { "heading_level" => level })

  def parents(units) = described_class.nest(units).map(&:parent_section_id)

  it "nests a skipped level under the nearest shallower heading" do
    expect(parents([unit("a", 1), unit("b", 3), unit("c", 2)])).to eq([nil, "a", "a"])
  end

  it "closes a scope at a heading of the same or a higher level" do
    expect(parents([unit("a", 2), unit("b", 3), unit("c", 2), unit("d", 1)])).to eq([nil, "a", nil, nil])
  end

  it "gives a unit without a level no parent and does not open a scope" do
    expect(parents([unit("pre", nil), unit("a", 2), unit("x", nil), unit("b", 3)])).to eq([nil, nil, nil, "a"])
  end

  it "leaves a document that starts below the top level at the top" do
    expect(parents([unit("a", 3), unit("b", 3)])).to eq([nil, nil])
  end
end
