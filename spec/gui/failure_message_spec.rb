# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/sfl/gui/failure_message"

# A pure function with no Glimmer in it, so the "GUI needs a display" exemption
# the rest of lib/sfl/gui claims does not apply here (SIFT T-1).
RSpec.describe SFL::GUI::FailureMessage do
  describe ".call" do
    it "passes a String through unchanged" do
      expect(described_class.call("sidecar crashed")).to eq("sidecar crashed")
    end

    it "returns an empty String unchanged rather than treating it as unknown" do
      expect(described_class.call("")).to eq("")
    end

    it "humanizes a Symbol by replacing underscores with spaces" do
      expect(described_class.call(:pass_one_failed)).to eq("pass one failed")
    end

    it "leaves a Symbol with no underscores alone" do
      expect(described_class.call(:timeout)).to eq("timeout")
    end

    # The shape Core::Pipeline actually returns, and the reason this module
    # exists: #inspect would render it as Ruby syntax inside a msg_box_error.
    it "joins a flat Array with colons, formatting each part by its own type" do
      expect(described_class.call([:pass_one_failed, "sidecar crashed"]))
        .to eq("pass one failed: sidecar crashed")
    end

    it "flattens a nested Array before formatting" do
      expect(described_class.call([:pass_one_failed, ["sidecar crashed", :retry_exhausted]]))
        .to eq("pass one failed: sidecar crashed: retry exhausted")
    end

    it "flattens arbitrarily deep nesting" do
      expect(described_class.call([[[:a_b], ["c"]], :d])).to eq("a b: c: d")
    end

    it "drops parts that format to an empty String instead of leaving stray colons" do
      expect(described_class.call([:pass_one_failed, "", "sidecar crashed"]))
        .to eq("pass one failed: sidecar crashed")
    end

    it "renders an Array whose parts all format to empty as an empty String" do
      expect(described_class.call(["", ""])).to eq("")
    end

    it "renders an empty Array as an empty String" do
      expect(described_class.call([])).to eq("")
    end

    # nil reaches here when a Failure carries no payload at all.
    it "renders nil as a human-readable placeholder" do
      expect(described_class.call(nil)).to eq("unknown error")
    end

    # nil inside an Array takes the recursive branch, not the top-level one.
    it "renders a nil nested in an Array as the same placeholder" do
      expect(described_class.call([:pass_one_failed, nil]))
        .to eq("pass one failed: unknown error")
    end

    it "falls back to to_s for any other type" do
      expect(described_class.call(42)).to eq("42")
    end

    it "falls back to to_s for an exception payload" do
      expect(described_class.call(StandardError.new("boom"))).to eq("boom")
    end

    it "falls back to to_s for a Hash payload" do
      expect(described_class.call({ code: 500 })).to eq({ code: 500 }.to_s)
    end
  end

  # SIFT I-2 switched this module from `extend self` to inline module_function,
  # matching the other 13 modules in lib/. That makes the instance methods
  # private, so a mixin-style caller would break — this pins the module-function
  # calling convention every existing call site actually uses.
  it "exposes .call as a module function" do
    expect(described_class).to respond_to(:call)
  end
end
