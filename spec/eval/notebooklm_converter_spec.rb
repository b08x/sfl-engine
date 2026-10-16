# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe SFL::Eval::NotebooklmConverter do
  it "maps speaker/text captions to name/mes lines and leaves the source intact" do
    Dir.mktmpdir do |dir|
      source = File.join(dir, "in.jsonl")
      dest = File.join(dir, "out.jsonl")
      File.write(source, %({"index":0,"speaker":"Speaker 1 (M)","text":"Hello."}\n\n{"index":1,"speaker":"Speaker 2 (F)","text":"Hi."}\n))
      original = File.read(source)

      expect(described_class.call(source, dest)).to eq(2)
      rows = File.readlines(dest).map { |line| JSON.parse(line) }
      expect(rows.first).to eq("name" => "Speaker 1 (M)", "mes" => "Hello.", "is_user" => false)
      expect(rows.map { |row| row["mes"] }).to eq(["Hello.", "Hi."])
      expect(File.read(source)).to eq(original)
    end
  end
end
