# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Null::SectionRegistry do
  subject(:registry) { described_class.new }

  it "runs the transaction block and returns its value" do
    expect(registry.transaction { :done }).to eq(:done)
  end

  it "records nothing" do
    expect(registry.register(SFL::Core::Types::Unit.new(section_id: "a#b", text: "t"), 1)).to be_nil
  end
end
