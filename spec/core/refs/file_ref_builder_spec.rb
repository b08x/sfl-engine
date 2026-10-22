# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe SFL::Core::Refs::FileRefBuilder do
  let(:root) { Dir.mktmpdir }
  let(:file) { File.join(root, "chat.jsonl") }

  before { File.write(file, "{}\n") }

  after { FileUtils.rm_rf(root) }

  describe ".call" do
    it "gives the same path_hint for a relative, ./relative and absolute spelling" do
      relative = Pathname(file).relative_path_from(Dir.pwd).to_s

      hints = [relative, "./#{relative}", file].map { |spelling| described_class.call(spelling).path_hint }

      expect(hints.uniq).to eq([File.expand_path(file)])
    end

    it "stores the expanded absolute path as path_hint" do
      relative = Pathname(file).relative_path_from(Dir.pwd).to_s

      expect(described_class.call(relative).path_hint).to eq(File.expand_path(file))
    end

    it "keeps the name, extension and file stats of the file" do
      ref = described_class.call(file)

      expect([ref.name, ref.extension, ref.size_bytes]).to eq(["chat", ".jsonl", File.size(file)])
    end
  end
end
