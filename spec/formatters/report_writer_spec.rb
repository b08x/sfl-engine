# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe SFL::Formatters::ReportWriter do
  let(:turn) { build_turn(turn_id: 1, speaker: "Alice") }
  let(:result) { build_analysis_result(metadata: { conversation_id: "conv-1" }, turns: [turn]) }

  it "writes the CSV/JSON/Markdown trio under output_dir and returns their paths" do
    Dir.mktmpdir do |dir|
      output_dir = File.join(dir, "reports")

      paths = described_class.write(result, output_dir)

      expect(paths.keys).to contain_exactly(:csv, :json, :markdown)
      expect(File).to exist(paths[:csv])
      expect(File).to exist(paths[:json])
      expect(File).to exist(paths[:markdown])
      expect(paths[:csv]).to eq(File.join(output_dir, "conversation_analysis.csv"))
    end
  end

  it "creates output_dir if it does not already exist" do
    Dir.mktmpdir do |dir|
      output_dir = File.join(dir, "nested", "reports")

      expect { described_class.write(result, output_dir) }.not_to raise_error
      expect(Dir).to exist(output_dir)
    end
  end
end
