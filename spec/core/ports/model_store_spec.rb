# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::ModelStore do
  let(:adapter) { Class.new { include SFL::Core::Ports::ModelStore }.new }

  it "requires #sync, #list, #assignments and #assign from an adapter" do
    expect { adapter.sync([], providers: []) }.to raise_error(NotImplementedError)
    expect { adapter.list }.to raise_error(NotImplementedError)
    expect { adapter.assignments }.to raise_error(NotImplementedError)
    expect { adapter.assign(:embedding, provider: "ollama", model_id: "m") }.to raise_error(NotImplementedError)
  end
end
