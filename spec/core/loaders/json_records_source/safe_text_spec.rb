# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::JsonRecordsSource::SafeText do
  it "replaces each control character, including a line break, with one space" do
    expect(described_class.line("a\nb\rc\td")).to eq("a b c d")
  end

  it "cuts a key to 64 characters after sanitizing" do
    expect(described_class.key("x\n#{'a' * 100}")).to eq("x #{'a' * 62}")
  end
end
