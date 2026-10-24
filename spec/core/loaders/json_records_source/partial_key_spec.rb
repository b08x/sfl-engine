# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::JsonRecordsSource::PartialKey do
  it "reads a uuid that opens the record" do
    expect(described_class.call(%({"uuid": "c-omega", "chat_messages": [{))).to eq("c-omega")
  end

  it "returns nil when the uuid is not complete" do
    expect(described_class.call(%({"uu))).to be_nil
  end

  it "returns nil for a uuid with an escape, so the value is never guessed" do
    expect(described_class.call(%({"uuid": "c\\u002d", "chat_messages": [))).to be_nil
  end
end
