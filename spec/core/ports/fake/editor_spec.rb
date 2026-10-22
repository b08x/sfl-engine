# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Fake::Editor do
  it "records the text and returns the configured result" do
    expect(described_class.new.edit("a")).to eq("a")
    expect(described_class.new(result: "b").edit("a")).to eq("b")
    editor = described_class.new(result: lambda(&:upcase))

    expect(editor.edit("a")).to eq("A")
    expect(editor.edited).to eq(["a"])
  end
end
