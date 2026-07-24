# frozen_string_literal: true

require "spec_helper"
require "socket"
require "stringio"

RSpec.describe SFL::Boot::LangfuseReachability do
  describe ".reachable?" do
    it "returns true when something is actually listening on the host:port" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]

      expect(described_class.reachable?("http://127.0.0.1:#{port}")).to be(true)
    ensure
      server&.close
    end

    it "returns false when nothing is listening (connection refused)" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      server.close # now guaranteed closed/refusing on this port

      expect(described_class.reachable?("http://127.0.0.1:#{port}")).to be(false)
    end

    it "returns false for an unparseable host" do
      expect(described_class.reachable?("not a url")).to be(false)
    end
  end

  describe ".decide" do
    let(:env) do
      { "LANGFUSE_PUBLIC_KEY" => "pk", "LANGFUSE_SECRET_KEY" => "sk", "LANGFUSE_HOST" => "http://example.invalid" }
    end

    it "returns :traced when Langfuse keys are not configured at all" do
      expect(described_class.decide(env: {}, tty: true)).to eq(:traced)
    end

    it "returns :traced when the endpoint is reachable, without prompting" do
      allow(described_class).to receive(:reachable?).and_return(true)

      expect(described_class.decide(env:, tty: true)).to eq(:traced)
    end

    it "returns :skip_tracing automatically in a non-interactive session" do
      allow(described_class).to receive(:reachable?).and_return(false)

      expect { expect(described_class.decide(env:, tty: false)).to eq(:skip_tracing) }
        .to output(/Cannot reach Langfuse/).to_stderr
    end

    it "returns :skip_tracing when the user answers y at the interactive prompt" do
      allow(described_class).to receive(:reachable?).and_return(false)
      input = StringIO.new("y\n")

      result = nil
      expect { result = described_class.decide(env:, tty: true, input:) }.to output.to_stderr
      expect(result).to eq(:skip_tracing)
    end

    it "returns :cancel when the user declines (or gives any other answer) at the prompt" do
      allow(described_class).to receive(:reachable?).and_return(false)
      input = StringIO.new("n\n")

      result = nil
      expect { result = described_class.decide(env:, tty: true, input:) }.to output.to_stderr
      expect(result).to eq(:cancel)
    end

    it "returns :cancel when stdin is closed/empty at the prompt" do
      allow(described_class).to receive(:reachable?).and_return(false)
      input = StringIO.new("")

      result = nil
      expect { result = described_class.decide(env:, tty: true, input:) }.to output.to_stderr
      expect(result).to eq(:cancel)
    end
  end
end
