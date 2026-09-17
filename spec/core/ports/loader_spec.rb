# frozen_string_literal: true

RSpec.describe SFL::Core::Ports::Loader do
  describe SFL::Core::Ports::Null::Loader do
    subject { described_class.new }

    it_behaves_like "a loader"

    it "yields zero units" do
      expect(subject.units).to be_empty
    end
  end

  describe SFL::Core::Ports::Fake::Loader do
    subject { described_class.new([unit]) }

    let(:unit) do
      SFL::Core::Types::Unit.new(
        document_id: "doc-1", text: "Hello", heading: nil,
        metadata: {}, speaker: nil, sent_at: nil, is_user: nil
      )
    end

    it_behaves_like "a loader"

    it "yields the provided units" do
      expect(subject.units).to eq([unit])
    end

    it "yields units one at a time via each_unit" do
      expect { |b| subject.each_unit(&b) }.to yield_successive_args(unit)
    end
  end

  describe "Core::Loaders::Source alias" do
    let(:source_class) do
      Class.new do
        include SFL::Core::Loaders::Source
      end
    end

    it "includes the Loader port" do
      expect(source_class.ancestors).to include(described_class)
    end

    it "raises NotImplementedError on bare #each_unit" do
      instance = source_class.new
      expect { instance.each_unit }.to raise_error(NotImplementedError, /must implement #each_unit/)
    end

    it "provides #units as a free method" do
      instance = source_class.new
      expect { instance.units }.to raise_error(NotImplementedError)
    end
  end
end
