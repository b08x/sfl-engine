# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe SFL::Formatters::BaseFormatter do
  describe "#initialize" do
    it "exposes the given result via #result" do
      result = double("result") # rubocop:disable RSpec/VerifiedDoubles -- BaseFormatter treats result as an opaque value

      expect(described_class.new(result).result).to be(result)
    end
  end

  describe "#render" do
    it "raises NotImplementedError" do
      expect { described_class.new(nil).render }.to raise_error(NotImplementedError, /Subclasses must implement/)
    end
  end

  describe "#write_to" do
    it "writes #render's output to the given path" do
      subclass = Class.new(described_class) do
        def render
          "rendered content"
        end
      end

      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.txt")
        subclass.new(nil).write_to(path)

        expect(File.read(path)).to eq("rendered content")
      end
    end
  end
end
