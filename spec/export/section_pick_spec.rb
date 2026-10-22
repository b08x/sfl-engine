# frozen_string_literal: true

require_relative "export_helper"

RSpec.describe SFL::Export::SectionPick do
  it "has the label as speaker for a turn section only" do
    turn, heading = ExportSpecSupport.papers_picks.values_at(3, 0)

    expect(turn.speaker).to eq("Alice")
    expect(heading.speaker).to be_nil
  end
end
