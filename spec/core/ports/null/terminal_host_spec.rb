# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Null::TerminalHost do
  it "opens no tab and shows no image" do
    host = described_class.new

    expect(host.launch_tab(cmd: ["true"], cwd: "/", title: "t")).to be(false)
    expect(host.show_image("/a.png")).to be(false)
  end
end
