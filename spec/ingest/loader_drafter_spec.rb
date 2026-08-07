# frozen_string_literal: true

require "spec_helper"
require "ruby_llm"
require "tmpdir"
require "fileutils"

RSpec.describe SFL::Ingest::LoaderDrafter do
  subject(:drafter) { described_class.new(chat: fake_chat, loaders_dir:, docs_dir:) }

  let(:fake_chat) { instance_double(RubyLLM::Chat) }
  let(:tmpdir) { Dir.mktmpdir }
  let(:loaders_dir) { File.join(tmpdir, "loaders") }
  let(:docs_dir) { File.join(tmpdir, "docs") }

  after { FileUtils.remove_entry(tmpdir) }

  describe "#draft" do
    it "writes a candidate loader file and a review doc, returning both paths" do
      fake_response = instance_double(RubyLLM::Message, content: {
        "class_name" => "GenericJsonlChatSource",
        "ruby_source" => "# frozen_string_literal: true\n\nmodule SFL\n  module Core\n    module Loaders\n      " \
          "class GenericJsonlChatSource\n        include Source\n\n        def each_unit\n        " \
          "end\n      end\n    end\n  end\nend\n",
        "field_mapping_explanation" => "role -> speaker, content -> text, no timestamp field found",
        "confidence" => 0.6,
      })
      allow(fake_chat).to receive_messages(with_schema: fake_chat, ask: fake_response)

      result = drafter.draft("{\"role\":\"user\",\"content\":\"hi\"}\n", "export-dump/weird_chat.jsonl")

      expect(fake_chat).to have_received(:with_schema).with(SFL::LLM::Schemas::LoaderDraftSchema)
      expect(fake_chat).to have_received(:ask) do |prompt|
        expect(prompt).to include("export-dump/weird_chat.jsonl")
      end
      expect(result[:loader_path]).to eq(File.join(loaders_dir, "generic_jsonl_chat_source.rb"))
      expect(result[:doc_path]).to eq(File.join(docs_dir, "generic_jsonl_chat_source.md"))
      expect(File.read(result[:loader_path])).to include("class GenericJsonlChatSource")
      expect(File.read(result[:doc_path])).to include("role -> speaker, content -> text")
    end

    it "raises Ingest::LoaderDrafter::Error, without writing files, on an LLM failure" do
      allow(fake_chat).to receive(:with_schema).and_return(fake_chat)
      allow(fake_chat).to receive(:ask).and_raise(RubyLLM::Error, "rate limited")

      expect { drafter.draft("sample", "some/path.ndjson") }.to raise_error(described_class::Error, /rate limited/)
      expect(Dir.exist?(loaders_dir)).to be(false)
    end

    it "raises Ingest::LoaderDrafter::Error, without writing files, when the LLM returns a " \
      "class_name containing path-traversal segments (untrusted output feeding a filesystem path)" do
      fake_response = instance_double(RubyLLM::Message, content: {
        "class_name" => "../../etc/passwd",
        "ruby_source" => "# whatever",
        "field_mapping_explanation" => "n/a",
        "confidence" => 0.5,
      })
      allow(fake_chat).to receive_messages(with_schema: fake_chat, ask: fake_response)

      expect { drafter.draft("sample", "some/path.ndjson") }.to raise_error(described_class::Error, /class_name/)
      expect(Dir.exist?(loaders_dir)).to be(false)
    end

    it "raises Ingest::LoaderDrafter::Error, without writing files, when the LLM returns a " \
      "class_name that isn't a bare PascalCase identifier" do
      fake_response = instance_double(RubyLLM::Message, content: {
        "class_name" => "not valid; rm -rf /",
        "ruby_source" => "# whatever",
        "field_mapping_explanation" => "n/a",
        "confidence" => 0.5,
      })
      allow(fake_chat).to receive_messages(with_schema: fake_chat, ask: fake_response)

      expect { drafter.draft("sample", "some/path.ndjson") }.to raise_error(described_class::Error, /class_name/)
      expect(Dir.exist?(loaders_dir)).to be(false)
    end
  end
end
