# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::SillyTavernSource::SendDate do
  describe ".parse" do
    it "converts a summer date with the EDT offset" do
      expect(described_class.parse("June 19, 2024 2:22pm").iso8601).to eq("2024-06-19T18:22:00Z")
    end

    it "converts a winter date with the EST offset" do
      expect(described_class.parse("January 5, 2024 9:05am").iso8601).to eq("2024-01-05T14:05:00Z")
    end

    it "accepts an abbreviated, uppercase month name" do
      expect(described_class.parse("SEP 5, 2024 12:15am").iso8601).to eq("2024-09-05T04:15:00Z")
    end

    it "returns nil for nil, a non-string and a text that does not match the shape" do
      expect(described_class.parse(nil)).to be_nil
      expect(described_class.parse(12_345)).to be_nil
      expect(described_class.parse("yesterday")).to be_nil
    end

    it "returns nil for a minute of 60 and for hour 0 on a 12-hour clock" do
      expect(described_class.parse("June 19, 2024 2:60pm")).to be_nil
      expect(described_class.parse("June 19, 2024 0:22pm")).to be_nil
    end

    it "returns nil for a day that does not exist" do
      expect(described_class.parse("February 30, 2024 1:00pm")).to be_nil
    end
  end
end
