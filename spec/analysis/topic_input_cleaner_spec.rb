# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::TopicInputCleaner do
  describe "#call" do
    it "removes a leading speaker label and keeps the rest of the turn" do
      cleaner = described_class.new(speaker_names: ["Alice"])

      expect(cleaner.call(["Alice: Hello there"])).to eq(["Hello there"])
    end

    it "removes a tool-call trace line and keeps the surrounding text" do
      cleaner = described_class.new

      expect(cleaner.call(["Hello\n[tool_use] search {\"q\": 1}\nworld"])).to eq(["Hello world"])
    end

    it "removes a short system preamble line and keeps the following text" do
      cleaner = described_class.new

      expect(cleaner.call(["You are a helpful assistant.\nThe budget is fixed."])).to eq(["The budget is fixed."])
    end

    it "keeps a 'You are' line that is 200 characters or longer" do
      cleaner = described_class.new
      long_line = "You are #{'x' * 193}"

      expect(cleaner.call([long_line])).to eq([long_line])
    end

    it "removes a repeated header line and keeps the first occurrence" do
      cleaner = described_class.new

      expect(cleaner.call(["# Plan\nbody one\n# Plan\nbody two"])).to eq(["# Plan body one body two"])
    end

    it "collapses whitespace left by removals and strips both ends" do
      cleaner = described_class.new(speaker_names: ["Alice"])

      expect(cleaner.call(["  [Alice]   \n\n  Hello   \n  world  "])).to eq(["Hello world"])
    end

    it "leaves a speaker name or the word tool untouched when it appears mid-sentence" do
      cleaner = described_class.new(speaker_names: ["Alice"])
      texts = ["Thanks, Alice: that works", "Use the tool for this", "The Tool call: was logged mid line"]

      expect(cleaner.call(texts)).to eq(texts)
    end

    it "returns one output per input, in the same order, including an empty result" do
      cleaner = described_class.new(speaker_names: ["Alice"])

      expect(cleaner.call(["Alice: hi", "", "[tool_use] only", "Keep me"])).to eq(["hi", "", "", "Keep me"])
    end

    it "does not mutate the input strings" do
      cleaner = described_class.new(speaker_names: ["Alice"])
      texts = ["Alice: hi\n# H\n# H".dup, "You are a bot\nbody"]
      before = texts.map(&:dup)

      cleaner.call(texts)

      expect(texts).to eq(before)
    end

    it "matches speaker names case-insensitively and escapes regex characters in names" do
      cleaner = described_class.new(speaker_names: ["Dr. Smith", "bob"])

      expect(cleaner.call(["dr. smith: hi", "[BOB] hello", "Dr X: stays"])).to eq(["hi", "hello", "Dr X: stays"])
    end

    it "applies the boilerplate rules when speaker_names is empty and does not strip labels" do
      cleaner = described_class.new

      expect(cleaner.call(["You are a bot\nAlice: hi"])).to eq(["Alice: hi"])
    end
  end
end
