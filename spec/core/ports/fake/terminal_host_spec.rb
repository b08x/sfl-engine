# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Fake::TerminalHost do
  it "records tabs and images" do
    host = described_class.new

    expect(host.launch_tab(cmd: ["x"], cwd: "/", title: "t", env: { "A" => "1" })).to be(true)
    expect(host.show_image("/a.png")).to be(true)
    expect(host.tabs).to eq([{ cmd: ["x"], cwd: "/", title: "t", env: { "A" => "1" } }])
    expect(host.images).to eq(["/a.png"])
  end

  it "answers like the null host when not capable, and raises when given an error" do
    expect(described_class.new(capable: false).show_image("/a.png")).to be(false)
    expect { described_class.new(error: "boom").launch_tab(cmd: [], cwd: "/", title: "t") }
      .to raise_error(SFL::Core::Ports::TerminalHost::Error, "boom")
  end
end
