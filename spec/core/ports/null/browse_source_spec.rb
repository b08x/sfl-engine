# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Null::BrowseSource do
  subject(:source) { described_class.new }

  it "has nothing to browse" do
    expect([source.collections, source.documents(1), source.sections(1), source.clauses("s"), source.content_reviews])
      .to all(eq([]))
    expect([source.annotation_reviews, source.locate(["s"])]).to all(eq({}))
  end
end
