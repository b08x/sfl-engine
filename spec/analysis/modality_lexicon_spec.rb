# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::ModalityLexicon do
  subject(:lexicon) { described_class.new }

  # [text, expected band]. The band is the first marker found, after negation
  # and quoting are applied. Markers inside straight or curly double quotes do
  # not count.
  band_cases = [
    ["It might rain.", :low],
    ["Maybe we should go.", :low],
    ["Perhaps the best option.", :low],
    ["It could be worse.", :low],
    ["Possibly the best option.", :low],
    ["It may not work.", :low],
    ["I think so.", :low],
    ["It seems fine.", :low],
    ["I guess not.", :low],
    ["Maybe not.", :low],
    ["It probably works.", :median],
    ["It would be nice.", :median],
    ["It is likely.", :median],
    ["I believe you.", :median],
    ["This must be done.", :high],
    ["They definitely agreed.", :high],
    ["Clearly, the data says otherwise.", :high],
    ["Always check the logs.", :high],
    ["Never again.", :high],
    ["Of course it does.", :high],
    ["No doubt about it.", :high],
    ["It's certainly not the case.", :high],
    ["We can't possibly finish.", :high],
    ["We cannot possibly finish.", :high],
    ["It is not likely.", :median],
    ["The plan is clear.", nil],
    ["The sample is 40 rows.", nil],
    ["He said \"it might work\" yesterday.", nil],
    ["She wrote “definitely” in the margin.", nil],
    ["I do not think so.", nil],
    ["", nil],
    ["Mightier than the sword.", nil],
    ["MAYBE, just maybe.", :low],
    ["Nothing is certain here.", nil],
  ].freeze

  describe "#band" do
    band_cases.each do |text, expected|
      it "classifies #{text.inspect} as #{expected.inspect}" do
        expect(lexicon.band(text)).to eq(expected)
      end
    end

    it "returns nil for nil input rather than raising" do
      expect(lexicon.band(nil)).to be_nil
    end

    it "uses the first marker when a sentence has several" do
      expect(lexicon.band("Maybe this must be done.")).to eq(:low)
    end
  end

  describe "#contradiction?" do
    it "flags a high modality weight that the text hedges" do
      expect(lexicon.contradiction?(0.9, "It might work.")).to be(true)
    end

    it "flags a low modality weight that the text asserts" do
      expect(lexicon.contradiction?(0.2, "It must be done.")).to be(true)
    end

    it "does not flag a weight that agrees with the marker" do
      expect(lexicon.contradiction?(0.2, "It might work.")).to be(false)
      expect(lexicon.contradiction?(0.9, "It must be done.")).to be(false)
    end

    it "does not flag a median-band marker at any weight" do
      expect(lexicon.contradiction?(0.95, "It probably works.")).to be(false)
      expect(lexicon.contradiction?(0.05, "It probably works.")).to be(false)
    end

    it "does not flag a text with no marker" do
      expect(lexicon.contradiction?(0.9, "The plan is clear.")).to be(false)
    end

    it "uses inclusive thresholds: 0.8 with a low marker, 0.3 with a high marker" do
      expect(lexicon.contradiction?(0.8, "It might work.")).to be(true)
      expect(lexicon.contradiction?(0.3, "It must be done.")).to be(true)
    end

    it "does not flag just outside the thresholds" do
      expect(lexicon.contradiction?(0.79, "It might work.")).to be(false)
      expect(lexicon.contradiction?(0.31, "It must be done.")).to be(false)
    end
  end
end
