# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Null::Opener do
  it "does nothing" do
    expect(described_class.new.open("/a.png")).to be_nil
  end
end
