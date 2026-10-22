# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::BrowseSource do
  subject(:port) { Class.new { include SFL::Core::Ports::BrowseSource }.new }

  it "requires every reader from an adapter" do
    expect { port.collections }.to raise_error(NotImplementedError)
    expect { port.documents(1) }.to raise_error(NotImplementedError)
    expect { port.sections(1) }.to raise_error(NotImplementedError)
    expect { port.clauses("s") }.to raise_error(NotImplementedError)
    expect { port.content_reviews }.to raise_error(NotImplementedError)
    expect { port.annotation_reviews }.to raise_error(NotImplementedError)
    expect { port.locate([]) }.to raise_error(NotImplementedError)
  end
end
