# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::Source do
  let(:including_class) do
    Class.new do
      include SFL::Core::Loaders::Source
    end
  end

  describe "#each_unit" do
    it "raises NotImplementedError when not overridden" do
      expect { including_class.new.each_unit }.to raise_error(NotImplementedError)
    end
  end

  describe "#units" do
    it "collects everything #each_unit yields" do
      unit = SFL::Core::Types::Unit.new(document_id: "doc-1", text: "hi")
      klass = Class.new do
        include SFL::Core::Loaders::Source

        define_method(:each_unit) { |&blk| [unit].each(&blk) }
      end

      expect(klass.new.units).to eq([unit])
    end
  end
end
