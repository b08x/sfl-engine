# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe SFL::CLI do
  describe ".parse json-records" do
    it "takes one or more files as the input list, not a single input" do
      parsed = described_class.parse(%w[json-records a/conversations.json b/conversations-001.json])

      expect(parsed[:command]).to eq(:json_records)
      expect(parsed[:input]).to eq(%w[a/conversations.json b/conversations-001.json])
    end

    it "defaults the collection to the basename of the first file's directory" do
      parsed = described_class.parse(%w[json-records /exports/conversations-000/conversations.json])

      expect(parsed[:options][:collection]).to eq("conversations-000")
    end

    it "honors --collection and --disable-tracing wherever they appear" do
      parsed = described_class.parse(%w[json-records --collection chats x.json --disable-tracing])

      expect(parsed[:input]).to eq(%w[x.json])
      expect(parsed[:options]).to include(collection: "chats", disable_tracing: true)
    end

    it "raises UsageError when no file is given" do
      expect { described_class.parse(%w[json-records --collection chats]) }
        .to raise_error(described_class::UsageError, /requires one or more JSON files/)
    end
  end

  describe ".run_json_records" do
    let(:db) { SFL::Store::StoreTestDb.db }
    let(:logger) { instance_double(SFL::Core::Ports::Logger, warn: nil, error: nil) }
    let(:boot_result) { SFL::Boot::Result.new(db:, llm_config: nil, lm_factory: nil, embedder: nil, classifier: nil) }
    let(:dir) { Dir.mktmpdir }
    let(:output) { StringIO.new }

    before do
      SFL::Store::StoreTestDb.clean!
      allow(SFL::Boot).to receive(:call).and_return(boot_result)
      allow(described_class).to receive(:build_collaborators).and_return([logger, nil, nil])
      allow($stdout).to receive(:puts) { |*args| output.puts(*args) }
    end

    after { FileUtils.remove_entry(dir) }

    def msg(text) = { "sender" => "human", "text" => text }
    def convo(uuid, *messages) = { "uuid" => uuid, "chat_messages" => messages }

    def write_export(name, content)
      path = File.join(dir, name)
      File.write(path, JSON.generate(content))
      path
    end

    it "boots without an LLM, writes the records, and returns 0 when every file is intact" do
      path = write_export("conversations.json", [convo("c-alpha", msg("one"), msg("two")), convo("c-beta", msg("three"))])

      status = described_class.run_json_records([path], collection: "chats", disable_tracing: false)

      expect(SFL::Boot).to have_received(:call).with(require_llm: false, require_tracing: true, require_schema: true)
      expect(status).to eq(0)
      expect(db[:documents].select_map(:document_key)).to contain_exactly("c-alpha", "c-beta")
      expect(db[:collections].select_map(:name)).to eq(["chats"])
      expect(output.string).to include("Ingested files: 1", "processed 3, skipped none, failed 0, stale_removed 0")
    end

    it "prints a skipped line for each empty message and the grouped reason count" do
      path = write_export("conversations.json", [convo("c-alpha", msg(""), msg("kept"))])

      described_class.run_json_records([path], collection: "chats", disable_tracing: false)

      expect(output.string).to include("skipped #{File.basename(path)} record_index=0 reason=text_empty")
      expect(output.string).to include("processed 1, skipped text_empty 1, failed 0")
    end

    it "prints the failed entry with its byte offset and returns 1 when a file is truncated" do
      path = File.join(dir, "conversations.json")
      File.write(path, %([{"uuid": "c-alpha", "chat_messages": [{"text": "x"}]}, {"uuid": "c-beta", "chat_m))

      status = described_class.run_json_records([path], collection: "chats", disable_tracing: false)

      expect(status).to eq(1)
      expect(output.string).to match(/failed conversations\.json byte_offset=\d+ reason=truncated/)
      expect(output.string).to include("processed 0, skipped none, failed 1")
      expect(db[:documents].count).to eq(0)
    end

    it "raises UsageError for a file that does not exist" do
      expect { described_class.run_json_records([File.join(dir, "missing.json")], collection: "chats", disable_tracing: false) }
        .to raise_error(described_class::UsageError, /no such file/)
    end
  end
end
