# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe SFL::Ingest::DeterministicRules do
  def write(dir, name, content)
    path = File.join(dir, name)
    File.write(path, content)
    path
  end

  describe ".classify" do
    it "matches a .md file as knowledge_base/documentation-shaped" do
      Dir.mktmpdir do |dir|
        path = write(dir, "notes.md", "# Title\n\nSome text.")

        result = described_class.classify(path)

        expect(result).to eq(format: "markdown", mode: "knowledge_base", source_type: "vault_markdown")
      end
    end

    it "matches a .pdf file" do
      Dir.mktmpdir do |dir|
        path = write(dir, "doc.pdf", "%PDF-1.4 fake")

        result = described_class.classify(path)

        expect(result).to include(format: "pdf", mode: "knowledge_base", source_type: "vault_pdf")
      end
    end

    it "matches a .canvas file" do
      Dir.mktmpdir do |dir|
        path = write(dir, "board.canvas", "{}")

        result = described_class.classify(path)

        expect(result).to include(format: "canvas", mode: "knowledge_base", source_type: "vault_canvas")
      end
    end

    it "matches a native chat file (.jsonl) as conversation-shaped" do
      Dir.mktmpdir do |dir|
        path = write(dir, "chat.jsonl", %({"name":"a","mes":"hi","send_date":"2026-01-01"}\n))

        result = described_class.classify(path)

        expect(result).to eq(format: "chat_native", mode: "conversation", source_type: "chat_native")
      end
    end

    it "matches a ChatGPT export .json (mapping key) as conversation-shaped" do
      Dir.mktmpdir do |dir|
        # Top-level array of conversation objects, matching real ChatGPT export shape and
        # Analysis::ChatExportExpander.detect_format's actual parsing contract (a bare
        # top-level Hash with "mapping" is not recognized — only Array, or {"conversations": [...]}).
        path = write(dir, "export.json", %([{"mapping": {"a": {"message": null}}}]))

        result = described_class.classify(path)

        expect(result).to eq(format: "chatgpt_export", mode: "conversation", source_type: "chat_chatgpt")
      end
    end

    it "matches a Claude export .json (chat_messages key) as conversation-shaped" do
      Dir.mktmpdir do |dir|
        path = write(dir, "export.json", %([{"chat_messages": [{"text": "hi"}]}]))

        result = described_class.classify(path)

        expect(result).to eq(format: "claude_export", mode: "conversation", source_type: "chat_claude")
      end
    end

    it "returns nil for an unrecognized .json shape" do
      Dir.mktmpdir do |dir|
        path = write(dir, "data.json", %({"unrelated": "shape"}))

        expect(described_class.classify(path)).to be_nil
      end
    end

    it "returns nil, not a raised error, for malformed .json" do
      Dir.mktmpdir do |dir|
        path = write(dir, "broken.json", "{not valid json")

        expect(described_class.classify(path)).to be_nil
      end
    end

    it "matches an image file as knowledge_base-shaped" do
      Dir.mktmpdir do |dir|
        path = write(dir, "diagram.png", "fake png bytes")

        result = described_class.classify(path)

        expect(result).to eq(format: "image", mode: "knowledge_base", source_type: "vault_image")
      end
    end

    it "returns nil for an unrecognized extension (e.g. .jsonl-like new export format)" do
      Dir.mktmpdir do |dir|
        path = write(dir, "weird_chat.ndjson", %({"role": "user", "content": "hi"}\n))

        expect(described_class.classify(path)).to be_nil
      end
    end
  end
end
