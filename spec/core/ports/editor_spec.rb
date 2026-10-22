# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Editor do
  it "requires #edit from an adapter" do
    expect { Class.new { include SFL::Core::Ports::Editor }.new.edit("t") }.to raise_error(NotImplementedError)
  end
end
