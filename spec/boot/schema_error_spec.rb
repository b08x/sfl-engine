# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Boot::SchemaError do
  it "is a Boot::Error, so existing rescues still catch it" do
    expect(described_class.ancestors).to include(SFL::Boot::Error)
  end
end
