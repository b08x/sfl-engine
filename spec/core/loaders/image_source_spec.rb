# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::ImageSource do
  let(:path) { "spec/fixtures/loaders/sample.png" }
  let(:chat) { double("chat", ask: response) } # rubocop:disable RSpec/VerifiedDoubles -- ImageSource#chat is a duck (#ask), not tied to a real RubyLLM class
  let(:response) { double("response", content: "A diagram showing a three-stage pipeline.") } # rubocop:disable RSpec/VerifiedDoubles

  it "is a Loaders::Source" do
    expect(described_class.new(path, chat:)).to be_a(SFL::Core::Loaders::Source)
  end

  it "yields one Unit built from the vision description" do
    units = described_class.new(path, chat:).units

    expect(units.size).to eq(1)
    expect(units.first.text).to eq("A diagram showing a three-stage pipeline.")
    expect(units.first.document_id).to eq("sample#image")
  end

  it "passes the image path to the chat as an attachment" do
    described_class.new(path, chat:).units

    expect(chat).to have_received(:ask).with(described_class::VISION_PROMPT, with: { image: path })
  end

  it "labels metadata annotation_source truthfully as not vision_failed on success" do
    unit = described_class.new(path, chat:).units.first

    expect(unit.metadata["vision_failed"]).to be(false)
  end

  context "when the vision call raises" do
    let(:chat) { double("chat") } # rubocop:disable RSpec/VerifiedDoubles

    before { allow(chat).to receive(:ask).and_raise(StandardError, "rate limited") }

    it "falls back to a filename/format stub and flags vision_failed truthfully" do
      unit = described_class.new(path, chat:).units.first

      expect(unit.text).to include("PNG image file")
      expect(unit.metadata["vision_failed"]).to be(true)
    end
  end
end
