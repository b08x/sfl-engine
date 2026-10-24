# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::JsonRecordsSource::Failure do
  subject(:failure) { described_class.new(file: "a.json", reason: "truncated", byte_offset: 42, partial: "{") }

  it "is a Loaders::Error" do
    expect(failure).to be_a(SFL::Core::Loaders::Error)
  end

  it "names the file, the reason and the byte offset in its message" do
    expect(failure.message).to eq("a.json: truncated at byte 42")
  end

  it "exposes its fields" do
    expect(failure).to have_attributes(file: "a.json", reason: "truncated", byte_offset: 42, partial: "{")
  end
end
