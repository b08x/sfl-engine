# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"

# Test doubles for the sidecar process, runner and logger. No real process is ever spawned.
module BertopicSidecarFakes
  # Scripted stand-in for one spawned child. `steps` is consumed one per request
  # line written to stdin: a Hash is sent back with the request's id merged in,
  # :crash (or running out of steps) sends nothing, so the next read hits EOF.
  class FakeBertopicProcess
    READY_LINE = '{"type": "ready", "model": "bertopic"}'

    attr_reader :stdin, :stdout, :wait_thread, :requests

    def initialize(steps: [], ready: READY_LINE)
      @steps = steps
      @requests = []
      @lines = ready ? [ready] : []
      @stdin = FakeStdin.new(self)
      @stdout = FakeStdout.new(@lines)
      @wait_thread = FakeWaitThread.new
    end

    def receive(line)
      request = JSON.parse(line)
      @requests << request
      step = @steps.shift
      @lines << JSON.generate(step.merge("id" => request["id"])) if step.is_a?(Hash)
    end

    class FakeStdin
      def initialize(process) = @process = process
      def puts(line) = @process.receive(line)
      def close = nil
    end

    class FakeStdout
      def initialize(lines) = @lines = lines
      def gets = @lines.shift
      def close = nil
    end

    class FakeWaitThread
      def pid = 4242
      def join(_timeout = nil) = self
    end
  end

  # Records every spawn and hands out the scripted processes in order.
  class FakeBertopicRunner
    attr_reader :commands

    def initialize(*processes)
      @planned = processes
      @commands = []
      @processes = []
    end

    def call(command)
      @commands << command
      process = @planned.shift || raise("FakeBertopicRunner has no process scripted for this spawn")
      @processes << process
      [process.stdin, process.stdout, process.wait_thread]
    end

    def requests = @processes.flat_map(&:requests)
  end

  # Logger fake that keeps each call as { level:, message:, fields: }.
  class RecordingBertopicLogger < SFL::Core::Ports::Null::Logger
    attr_reader :records

    def initialize
      super
      @records = []
    end

    %i[debug info warn error fatal].each do |level|
      define_method(level) do |message = nil, **fields, &block|
        @records << { level:, message: message || block&.call, fields: }
      end
    end

    def entries(level) = @records.select { |record| record[:level] == level }
  end
end

RSpec.describe SFL::Analysis::BertopicSidecar do
  let(:command) { ["python3", "sidecar/bertopic/bertopic_sidecar.py"] }
  let(:logger) { BertopicSidecarFakes::RecordingBertopicLogger.new }
  let(:reply) do
    {
      "topics" => [0, 0, -1, 1],
      "topic_words" => { "0" => %w[cat dog], "1" => ["car"] },
      "outlier_topic" => -1,
    }
  end
  let(:uuid_pattern) { /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/ }

  def corpus(count)
    [Array.new(count) { |i| "turn #{i}" }, Array.new(count) { |i| [i.to_f, 1.0] }]
  end

  def build(runner:, max_restarts: 1)
    described_class.new(command:, logger:, runner:, max_restarts:)
  end

  # Guard: no spec may start a real process.
  before { allow(Open3).to receive(:popen2).and_raise("specs must not spawn the sidecar") }

  describe "#fit" do
    it "returns topics, Integer-keyed topic words and the non-outlier coverage" do
      runner = BertopicSidecarFakes::FakeBertopicRunner.new(BertopicSidecarFakes::FakeBertopicProcess.new(steps: [reply]))
      texts, embeddings = corpus(4)

      result = build(runner:).fit(texts:, embeddings:, seed: 7)

      expect(result).to eq(
        topics: [0, 0, -1, 1],
        topic_words: { 0 => %w[cat dog], 1 => ["car"] },
        coverage: 0.75
      )
    end

    it "sends one request line with the contract keys and nr_topics null when k is nil" do
      runner = BertopicSidecarFakes::FakeBertopicRunner.new(BertopicSidecarFakes::FakeBertopicProcess.new(steps: [reply]))
      texts, embeddings = corpus(4)

      build(runner:).fit(texts:, embeddings:, seed: 7)

      request = runner.requests.first
      expect(request.keys).to contain_exactly("id", "type", "texts", "embeddings", "nr_topics", "min_topic_size", "seed")
      expect(request["id"]).to match(uuid_pattern)
      expect(request["type"]).to eq("bertopic")
      expect(request["texts"]).to eq(texts)
      expect(request["embeddings"]).to eq(embeddings)
      expect(request["nr_topics"]).to be_nil
      expect(request["min_topic_size"]).to eq(2)
      expect(request["seed"]).to eq(7)
    end

    it "sends nr_topics as an Integer when k is given" do
      runner = BertopicSidecarFakes::FakeBertopicRunner.new(BertopicSidecarFakes::FakeBertopicProcess.new(steps: [reply]))
      texts, embeddings = corpus(4)

      build(runner:).fit(texts:, embeddings:, k: 3, seed: 7)

      expect(runner.requests[0]["nr_topics"]).to eq(3)
    end

    it "derives min_topic_size as max(2, texts.size / 10) and honours an explicit override" do
      thirty = reply.merge("topics" => Array.new(30) { |i| i.even? ? 0 : -1 })
      derived = BertopicSidecarFakes::FakeBertopicRunner.new(BertopicSidecarFakes::FakeBertopicProcess.new(steps: [thirty]))
      texts, embeddings = corpus(30)
      build(runner: derived).fit(texts:, embeddings:, seed: 1)
      expect(derived.requests[0]["min_topic_size"]).to eq(3)

      overridden = BertopicSidecarFakes::FakeBertopicRunner.new(BertopicSidecarFakes::FakeBertopicProcess.new(steps: [thirty]))
      build(runner: overridden).fit(texts:, embeddings:, seed: 1, min_topic_size: 5)
      expect(overridden.requests[0]["min_topic_size"]).to eq(5)
    end

    it "raises when the sidecar sends an error response, with the sidecar message" do
      runner = BertopicSidecarFakes::FakeBertopicRunner.new(BertopicSidecarFakes::FakeBertopicProcess.new(steps: [{ "error" => "embeddings must not be empty" }]))
      texts, embeddings = corpus(4)

      expect { build(runner:).fit(texts:, embeddings:, seed: 7) }
        .to raise_error(SFL::Analysis::Error, "embeddings must not be empty")
    end

    it "raises before sending anything when texts and embeddings differ in length" do
      runner = BertopicSidecarFakes::FakeBertopicRunner.new(BertopicSidecarFakes::FakeBertopicProcess.new(steps: [reply]))
      texts, = corpus(3)
      _, embeddings = corpus(2)

      expect { build(runner:).fit(texts:, embeddings:, seed: 7) }
        .to raise_error(SFL::Analysis::Error, /lengths differ/)
      expect(runner.commands).to be_empty
      expect(runner.requests).to be_empty
    end

    it "raises before sending anything when fewer than 2 texts are given" do
      runner = BertopicSidecarFakes::FakeBertopicRunner.new(BertopicSidecarFakes::FakeBertopicProcess.new(steps: [reply]))
      texts, embeddings = corpus(1)

      expect { build(runner:).fit(texts:, embeddings:, seed: 7) }
        .to raise_error(SFL::Analysis::Error, /at least 2 texts/)
      expect(runner.requests).to be_empty
    end

    it "raises when the sidecar returns a topic count that differs from the text count" do
      short = reply.merge("topics" => [0, 1])
      runner = BertopicSidecarFakes::FakeBertopicRunner.new(BertopicSidecarFakes::FakeBertopicProcess.new(steps: [short]))
      texts, embeddings = corpus(4)

      expect { build(runner:).fit(texts:, embeddings:, seed: 7) }
        .to raise_error(SFL::Analysis::Error, /2 topics for 4 texts/)
    end

    it "retries once after a mid-request crash, then succeeds on the restarted process" do
      runner = BertopicSidecarFakes::FakeBertopicRunner.new(
        BertopicSidecarFakes::FakeBertopicProcess.new(steps: [:crash]),
        BertopicSidecarFakes::FakeBertopicProcess.new(steps: [reply])
      )
      texts, embeddings = corpus(4)

      result = build(runner:).fit(texts:, embeddings:, seed: 7)

      expect(result[:topics]).to eq([0, 0, -1, 1])
      expect(runner.commands.size).to eq(2)
      expect(runner.requests.size).to eq(2)
      warning = logger.entries(:warn).first
      expect(warning[:fields]).to include(command: "python3 sidecar/bertopic/bertopic_sidecar.py", restarts: 0, max_restarts: 1)
    end

    it "raises once the restart budget is spent, and logs the restart with keyword fields" do
      runner = BertopicSidecarFakes::FakeBertopicRunner.new(
        BertopicSidecarFakes::FakeBertopicProcess.new(steps: [:crash]),
        BertopicSidecarFakes::FakeBertopicProcess.new(steps: [:crash])
      )
      texts, embeddings = corpus(4)

      expect { build(runner:).fit(texts:, embeddings:, seed: 7) }
        .to raise_error(SFL::Analysis::Error, /after 1 restart/)
      expect(runner.commands.size).to eq(2)
      expect(logger.entries(:warn).size).to eq(1)
      expect(logger.entries(:warn)[0][:fields]).to include(restarts: 0, max_restarts: 1)
      expect(logger.entries(:error).size).to eq(1)
    end

    it "raises without restarting when max_restarts is 0" do
      runner = BertopicSidecarFakes::FakeBertopicRunner.new(BertopicSidecarFakes::FakeBertopicProcess.new(steps: [:crash]))
      texts, embeddings = corpus(4)

      expect { build(runner:, max_restarts: 0).fit(texts:, embeddings:, seed: 7) }
        .to raise_error(SFL::Analysis::Error)
      expect(runner.commands.size).to eq(1)
    end

    it "requires the ready handshake and raises when the first line is not ready" do
      runner = BertopicSidecarFakes::FakeBertopicRunner.new(BertopicSidecarFakes::FakeBertopicProcess.new(ready: '{"type": "loading"}', steps: [reply]))
      texts, embeddings = corpus(4)

      expect { build(runner:).fit(texts:, embeddings:, seed: 7) }
        .to raise_error(SFL::Analysis::Error, /unexpected bertopic sidecar startup message/)
      expect(runner.requests).to be_empty
    end

    it "raises when the process exits before sending the ready line" do
      runner = BertopicSidecarFakes::FakeBertopicRunner.new(BertopicSidecarFakes::FakeBertopicProcess.new(ready: nil))
      texts, embeddings = corpus(4)

      expect { build(runner:).fit(texts:, embeddings:, seed: 7) }
        .to raise_error(SFL::Analysis::Error, /exited before signaling ready/)
    end
  end

  describe "#close" do
    it "shuts the process down and is idempotent" do
      runner = BertopicSidecarFakes::FakeBertopicRunner.new(BertopicSidecarFakes::FakeBertopicProcess.new(steps: [reply]))
      texts, embeddings = corpus(4)
      client = build(runner:)
      client.fit(texts:, embeddings:, seed: 7)

      expect { client.close }.not_to raise_error
      expect { client.close }.not_to raise_error
      expect(runner.commands.size).to eq(1)
    end

    it "does nothing when no process was ever started" do
      runner = BertopicSidecarFakes::FakeBertopicRunner.new

      expect { build(runner:).close }.not_to raise_error
      expect(runner.commands).to be_empty
    end
  end

  describe "construction" do
    it "does not spawn the process until #fit is called" do
      runner = BertopicSidecarFakes::FakeBertopicRunner.new

      build(runner:)

      expect(runner.commands).to be_empty
    end
  end
end
