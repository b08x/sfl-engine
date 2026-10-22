# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Null::Editor do
  it "returns the text unchanged" do
    expect(described_class.new.edit("same")).to eq("same")
  end
end
