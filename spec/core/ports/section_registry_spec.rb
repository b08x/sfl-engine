# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::SectionRegistry do
  let(:registry) { Class.new { include SFL::Core::Ports::SectionRegistry }.new }

  it "requires #transaction and #register from an adapter" do
    expect { registry.transaction { nil } }.to raise_error(NotImplementedError)
    expect { registry.register(nil, 0) }.to raise_error(NotImplementedError)
  end
end
