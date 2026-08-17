# frozen_string_literal: true

require "spec_helper"
require "dspy"

RSpec.describe SFL::CLI do
  describe ".run" do
    it "returns 0 and dispatches to run_<command> with the parsed input/options" do
      allow(described_class).to receive(:run_context)

      status = described_class.run(["context", "does it work?"])

      expect(status).to eq(0)
      expect(described_class).to have_received(:run_context).with("does it work?", hash_including(limit: 10))
    end

    it "prints usage and returns 1 for a UsageError (bad args, caught before any run_* call)" do
      expect { expect(described_class.run(["bogus"])).to eq(1) }.to output(/Unknown subcommand/).to_stderr
    end

    it "prints a clean [ERROR] message and returns 1 for a Boot::Error" do
      allow(described_class).to receive(:run_conversation).and_raise(SFL::Boot::Error, "DATABASE_URL is not set")

      expect { expect(described_class.run(%w[conversation input.jsonl])).to eq(1) }
        .to output(/\[ERROR\] DATABASE_URL is not set/).to_stderr
    end

    it "prints a clean [ERROR] message and returns 1 for an Analysis::Error" do
      allow(described_class).to receive(:run_conversation).and_raise(SFL::Analysis::Error, "compile failed")

      expect { expect(described_class.run(%w[conversation input.jsonl])).to eq(1) }
        .to output(/\[ERROR\] compile failed/).to_stderr
    end

    it "prints a provider-error message and returns 1 for a StandardError, no backtrace" do
      allow(described_class).to receive(:run_context).and_raise(SFL::LLM::Error, "slow down")

      expect { expect(described_class.run(%w[context q])).to eq(1) }
        .to output(/\[ERROR\] LLM provider error/).to_stderr
    end

    it "prints a clean [ERROR] message and returns 1 for a Timeout::Error" do
      allow(described_class).to receive(:run_context).and_raise(Timeout::Error, "context_synthesis exceeded")

      expect { expect(described_class.run(%w[context q])).to eq(1) }
        .to output(/\[ERROR\] context_synthesis exceeded/).to_stderr
    end
  end
end
