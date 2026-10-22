# frozen_string_literal: true

require "spec_helper"

# Fact 44: <collection>-<timestamp>.<extension>.
RSpec.describe SFL::Export::FileName do
  it "names the file after the collection and the time" do
    expect(described_class.call("papers", Time.new(2026, 10, 17, 9, 5, 3), "jsonl")).to eq("papers-20261017T090503.jsonl")
  end

  it "replaces characters that are unsafe in a file name" do
    expect(described_class.call("my papers/2026", Time.new(2026, 1, 2, 3, 4, 5), "md")).to eq("my_papers_2026-20260102T030405.md")
  end
end
