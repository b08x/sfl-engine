# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::Aggregations do
  subject(:host) { Class.new { include SFL::Analysis::Aggregations }.new }

  describe "#mean" do
    it "returns 0.5 for an empty array (neutral default)" do
      expect(host.mean([])).to eq(0.5)
    end

    it "returns the single value, rounded, for a single-element array" do
      expect(host.mean([0.333_333])).to eq(0.333)
    end

    it "returns the arithmetic mean of multiple values, rounded to 3 places" do
      expect(host.mean([0.1, 0.2, 0.3])).to eq(0.2)
    end

    it "rounds to exactly 3 decimal places" do
      expect(host.mean([1.0, 2.0, 4.0])).to eq(2.333)
    end
  end
end
