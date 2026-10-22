# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Fake::Opener do
  it "records opened paths" do
    opener = described_class.new
    opener.open("/a.png")

    expect(opener.opened).to eq(["/a.png"])
  end
end
