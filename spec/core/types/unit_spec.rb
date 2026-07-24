# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Types::Unit do
  it "requires document_id and text" do
    expect { described_class.new(document_id: "doc-1", text: "hello") }.not_to raise_error
  end

  it "defaults every turn/section-specific field so section-shaped and turn-shaped sources share one constructor" do
    unit = described_class.new(document_id: "doc-1", text: "hello")

    expect(unit.heading).to be_nil
    expect(unit.speaker).to be_nil
    expect(unit.is_user).to be_nil
    expect(unit.sent_at).to be_nil
    expect(unit.metadata).to eq({})
  end

  it "accepts turn-shaped fields" do
    unit = described_class.new(document_id: "doc-1", text: "hi", speaker: "Alice", is_user: true, sent_at: Time.now)

    expect(unit.speaker).to eq("Alice")
    expect(unit.is_user).to be(true)
  end
end
