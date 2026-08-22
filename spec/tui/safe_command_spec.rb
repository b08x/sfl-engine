# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe SFL::TUI::SafeCommand do
  let(:logger) { instance_spy(SFL::Core::Ports::JournaldLogger) }

  it "passes a message through unchanged" do
    message = SFL::TUI::Messages::Failed.new(:probe, "ok")

    expect(described_class.wrap(source: :probe) { message }.call).to be(message)
  end

  it "converts a raised exception into a Failed message instead of killing the command thread" do
    command = described_class.wrap(source: :retrieval, logger:) { raise SFL::Error, "pg down" }

    result = command.call

    expect(result).to be_a(SFL::TUI::Messages::Failed)
    expect(result.detail).to eq("SFL::Error: pg down")
    expect(logger).to have_received(:error).with(/retrieval/)
  end

  # Try(&) defaults to StandardError, which would let a NotImplementedError
  # from an unimplemented workspace hook escape onto the command thread — the
  # exact swallowed-background-exception mode this module exists to prevent.
  it "catches a non-StandardError (ScriptError) raise instead of letting it escape the command thread" do
    command = described_class.wrap(source: :board, logger:) { raise NotImplementedError, "Board#load" }

    result = command.call

    expect(result).to be_a(SFL::TUI::Messages::Failed)
    expect(result.detail).to eq("NotImplementedError: Board#load")
    expect(logger).to have_received(:error).with(/board/)
  end

  it "still lets Interrupt propagate so ctrl+c reaches the runner" do
    command = described_class.wrap(source: :probe) { raise Interrupt }

    expect { command.call }.to raise_error(Interrupt)
  end

  it "converts a Dry::Monads Failure into a Failed message" do
    command = described_class.wrap(source: :review) { Dry::Monads::Failure(:queue_empty) }

    expect(command.call).to have_attributes(source: :review, detail: "queue_empty")
  end
end
