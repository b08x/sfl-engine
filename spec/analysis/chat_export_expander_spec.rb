# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

RSpec.describe SFL::Analysis::ChatExportExpander do
  describe ".detect_format" do
    it "detects a ChatGPT export by its top-level \"mapping\" key" do
      expect(described_class.detect_format("spec/fixtures/loaders/chatgpt_conversations.json")).to eq(:chatgpt)
    end

    it "detects a Claude export by its top-level \"chat_messages\" key" do
      expect(described_class.detect_format("spec/fixtures/loaders/claude_conversations.json")).to eq(:claude)
    end

    it "returns nil for a file matching neither shape" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "not_an_export.json")
        File.write(path, JSON.dump([{ "foo" => "bar" }]))

        expect(described_class.detect_format(path)).to be_nil
      end
    end

    it "raises Core::Loaders::Error with the file path when the JSON is malformed, instead of " \
      "a bare JSON::ParserError with no indication of which file in a batch failed" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "broken.json")
        File.write(path, "{ not valid json")

        expect { described_class.detect_format(path) }
          .to raise_error(SFL::Core::Loaders::Error, /#{Regexp.escape(path)}.*invalid JSON/)
      end
    end

    it "descends into a {\"conversations\": [...]} envelope before inspecting the first element " \
      "(the Claude web-export wrapper shape, not just a bare top-level array)" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "enveloped.json")
        File.write(path, JSON.dump({ "conversations" => [{ "chat_messages" => [] }] }))

        expect(described_class.detect_format(path)).to eq(:claude)
      end
    end

    it "returns nil instead of raising for a non-array, non-conversations-envelope JSON root" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "scalar.json")
        File.write(path, JSON.dump("just a string"))

        expect(described_class.detect_format(path)).to be_nil
      end
    end

    it "returns nil instead of raising when the root array's first element is not a hash" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "not_hash_first.json")
        File.write(path, JSON.dump([1, 2, 3]))

        expect(described_class.detect_format(path)).to be_nil
      end
    end
  end

  describe ".expand" do
    it "raises Core::Loaders::Error for an unrecognized export shape" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "not_an_export.json")
        File.write(path, JSON.dump([{ "foo" => "bar" }]))

        expect do
          described_class.expand(path, dest_dir: dir)
        end.to raise_error(SFL::Core::Loaders::Error, /not a recognized/)
      end
    end

    it "writes one native {name:, mes:, send_date:, is_user:} JSONL file per ChatGPT conversation, " \
      "tagged source_type: chat_chatgpt, skipping conversations with no real turns" do
      Dir.mktmpdir do |dir|
        entries = described_class.expand("spec/fixtures/loaders/chatgpt_conversations.json", dest_dir: dir)

        expect(entries.size).to eq(1) # convo-2 has no real messages, produces no file
        entry = entries.first
        expect(entry[:source_type]).to eq("chat_chatgpt")
        expect(entry[:label]).to eq("explaining-rrf")

        lines = File.readlines(entry[:path]).map { |l| JSON.parse(l, symbolize_names: true) }
        expect(lines.map { |l| l[:name] }).to eq(%w[User ChatGPT])
        expect(lines.first[:mes]).to eq("What is reciprocal rank fusion?")
        expect(lines.first[:is_user]).to be true
      end
    end

    it "writes one JSONL file per Claude conversation, tagged source_type: chat_claude" do
      Dir.mktmpdir do |dir|
        entries = described_class.expand("spec/fixtures/loaders/claude_conversations.json", dest_dir: dir)

        expect(entries.size).to eq(2)
        expect(entries.map { |e| e[:source_type] }).to eq(%w[chat_claude chat_claude])
        first_lines = File.readlines(entries.first[:path]).map { |l| JSON.parse(l, symbolize_names: true) }
        expect(first_lines.first[:mes]).to eq("Why does this test fail intermittently?")
      end
    end

    it "disambiguates two conversations sharing the same title by conversation id, " \
      "instead of the second silently truncating the first's already-written file" do
      Dir.mktmpdir do |dir|
        source_path = File.join(dir, "export.json")
        File.write(source_path, JSON.dump(duplicate_title_chatgpt_export))

        entries = described_class.expand(source_path, dest_dir: dir, format: :chatgpt)

        expect(entries.size).to eq(2)
        expect(entries.map { |e| e[:path] }.uniq.size).to eq(2)
        first, second = entries.map { |e| File.readlines(e[:path]).map { |l| JSON.parse(l)["mes"] } }
        expect(first).to eq(["from convo A"])
        expect(second).to eq(["from convo B"])
      end
    end

    it "respects an explicit format: override instead of auto-detecting" do
      entries = described_class.expand("spec/fixtures/loaders/claude_conversations.json",
        dest_dir: Dir.mktmpdir, format: :claude)

      expect(entries.map { |e| e[:source_type] }).to all(eq("chat_claude"))
    end
  end

  def duplicate_title_chatgpt_export
    [
      chatgpt_convo(id: "conv-a", title: "Untitled", text: "from convo A"),
      chatgpt_convo(id: "conv-b", title: "Untitled", text: "from convo B"),
    ]
  end

  # rubocop:disable Metrics/MethodLength -- one flat fixture-shape literal, not branching logic.
  def chatgpt_convo(id:, title:, text:)
    {
      "id" => id,
      "title" => title,
      "create_time" => 1_780_000_000,
      "mapping" => {
        "root" => { "id" => "root", "message" => nil, "parent" => nil, "children" => ["user-1"] },
        "user-1" => {
          "id" => "user-1",
          "message" => { "author" => { "role" => "user" }, "content" => { "parts" => [text] }, "create_time" => nil },
          "parent" => "root",
          "children" => [],
        },
      },
    }
  end
  # rubocop:enable Metrics/MethodLength
end
