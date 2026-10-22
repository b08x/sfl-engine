# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Opener do
  it "requires #open from an adapter" do
    expect { Class.new { include SFL::Core::Ports::Opener }.new.open("p") }.to raise_error(NotImplementedError)
  end
end
