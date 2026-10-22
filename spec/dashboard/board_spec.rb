# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Dashboard::Board do
  it "holds the state and replaces it with what the update block returns" do
    board = described_class.new(1)

    expect(board.update { |n| n + 1 }).to eq(2)
    expect(board.state).to eq(2)
  end
end
