# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::CLI::StopFlag do
  it "starts unstopped" do
    expect(described_class.new.stopped?).to be(false)
  end

  it "reports stopped? true after #stop!" do
    flag = described_class.new
    flag.stop!
    expect(flag.stopped?).to be(true)
  end

  it "stays stopped across repeated #stop! calls" do
    flag = described_class.new
    flag.stop!
    flag.stop!
    expect(flag.stopped?).to be(true)
  end
end
