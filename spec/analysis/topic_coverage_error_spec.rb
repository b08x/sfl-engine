# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::TopicCoverageError do
  it "is an Analysis::Error, so callers rescuing the analysis error family catch it" do
    expect(described_class.ancestors).to include(SFL::Analysis::Error)
  end

  it "carries the message it was raised with" do
    expect { raise described_class, "coverage gate failed" }.to raise_error(described_class, "coverage gate failed")
  end
end
