# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Retriever do
  # A minimal class that includes the port without implementing it, to
  # verify the module's own NotImplementedError stub — mirrors how
  # Null::Retriever/PgHybridRetriever include this module and override
  # #retrieve; this spec covers what happens when an adapter doesn't.
  let(:unimplemented_adapter_class) do
    Class.new { include SFL::Core::Ports::Retriever }
  end

  it "raises NotImplementedError from the default #retrieve stub" do
    query = SFL::Core::Types::RetrievalQuery.new(query: "hello")

    expect { unimplemented_adapter_class.new.retrieve(query) }.to raise_error(NotImplementedError)
  end
end
