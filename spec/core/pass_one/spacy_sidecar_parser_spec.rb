# frozen_string_literal: true

require "spec_helper"
require "stringio"

# Spawns the real sidecar subprocess (python3 + spacy, verified present in
# this environment) rather than mocking the transport — the whole point of
# this class is the NDJSON handshake/restart contract, which a mock can't
# meaningfully stand in for.
RSpec.describe SFL::Core::PassOne::SpacySidecarParser do
  subject(:parser) { described_class.new(model: "en_core_web_sm") }

  after { parser.close }

  it "completes the startup handshake and returns clauses from #parse" do
    result = parser.parse("The dog chased the cat.")

    expect(result).to be_an(Array)
    expect(result.first).to be_a(SFL::Core::Types::SyntacticClause)
    expect(result.first.text).to eq("The dog chased the cat.")
  end

  it "resolves head_index positionally, not by matching head token text" do
    result = parser.parse("The dog chased the cat.")
    tokens = result.first.tokens

    first_the = tokens.find { |t| t.index == 0 }
    second_the = tokens.find { |t| t.index == 3 }
    root = tokens.find { |t| t.dep == "ROOT" }

    expect(first_the.head_index).not_to eq(second_the.head_index)
    expect(tokens[second_the.head_index].text).to eq("cat")
    expect(root.head_index).to eq(-1)
  end

  it "assigns document_id and sentence_index across multiple sentences" do
    result = parser.parse("The dog ran. The cat slept.", document_id: "doc-1")

    expect(result.map(&:document_id)).to eq(%w[doc-1 doc-1])
    expect(result.map(&:sentence_index)).to eq([0, 1])
  end

  it "returns an empty Array for blank text" do
    expect(parser.parse("")).to eq([])
    expect(parser.parse("   ")).to eq([])
  end

  it "restarts the subprocess and recovers after the child is killed" do
    pid = parser.__send__(:wait_thread).pid
    Process.kill("KILL", pid)

    result = parser.parse("It still works.")

    expect(result.first.text).to eq("It still works.")
  end

  describe "logging" do
    subject(:parser) { described_class.new(model: "en_core_web_sm", logger:) }

    let(:io) { StringIO.new }
    let(:logger) { SFL::Core::Ports::StandardLogger.new(io:, level: Logger::DEBUG) }

    it "logs info on a successful startup handshake" do
      parser # trigger the memoized subject's instantiation (nothing else in this example touches it)

      expect(io.string).to include("sidecar ready")
    end

    it "logs a warning when a crash forces a restart" do
      pid = parser.__send__(:wait_thread).pid
      Process.kill("KILL", pid)

      parser.parse("It still works.")

      expect(io.string).to include("restarting and retrying once")
    end
  end

  describe "env:" do
    it "passes env: through to Open3.popen2 alongside command:, so a vendored interpreter's " \
      "PYTHONPATH (Boot::Result#pass1_env) reaches the subprocess" do
      fake_env = { "PYTHONPATH" => "/vendored/python" }
      allow(Open3).to receive(:popen2).and_call_original

      described_class.new(model: "en_core_web_sm", env: fake_env).close

      expect(Open3).to have_received(:popen2).with(
        fake_env, "python3", described_class::DEFAULT_SCRIPT_PATH, "--model", "en_core_web_sm"
      )
    end
  end
end
