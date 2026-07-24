# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Types::RetrievalFilters do
  it "is constructible with no arguments, meaning no filter is applied" do
    filters = described_class.new

    expect(filters.to_h.compact).to eq({})
  end

  it "accepts every legacy filter attribute" do
    filters = described_class.new(
      mood: "imperative",
      min_modality: 0.2,
      max_modality: 0.8,
      min_tenor: 0.1,
      max_tenor: 0.9,
      process_type: "material",
      source_type: "chat_native"
    )

    expect(filters.to_h).to eq(
      mood: "imperative",
      min_modality: 0.2,
      max_modality: 0.8,
      min_tenor: 0.1,
      max_tenor: 0.9,
      process_type: "material",
      source_type: "chat_native"
    )
  end

  it "rejects an invalid mood value at construction time instead of silently matching nothing" do
    expect { described_class.new(mood: "not-a-real-mood") }.to raise_error(Dry::Struct::Error)
  end

  it "rejects an invalid process_type value at construction time" do
    expect { described_class.new(process_type: "not-a-real-process-type") }.to raise_error(Dry::Struct::Error)
  end

  it "rejects an out-of-range modality_weight at construction time" do
    expect { described_class.new(min_modality: 1.5) }.to raise_error(Dry::Struct::Error)
  end

  it "rejects an out-of-range tenor value at construction time" do
    expect { described_class.new(max_tenor: -0.5) }.to raise_error(Dry::Struct::Error)
  end

  it "raises on an unrecognized filter key instead of silently ignoring it (the legacy Hash bug this fixes)" do
    expect { described_class.new(typo_key: "imperative") }.to raise_error(Dry::Struct::Error)
  end
end
