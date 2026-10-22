# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::TerminalHost do
  let(:host) { Class.new { include SFL::Core::Ports::TerminalHost }.new }

  it "requires adapters to implement launch_tab and show_image" do
    expect { host.launch_tab(cmd: [], cwd: "/", title: "t") }.to raise_error(NotImplementedError)
    expect { host.show_image("/a.png") }.to raise_error(NotImplementedError)
  end

  it "has an error class under SFL::Error" do
    expect(described_class::Error.ancestors).to include(SFL::Error)
  end
end
