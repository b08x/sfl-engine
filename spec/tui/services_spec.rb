# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe SFL::TUI::Services do
  it "builds null collaborators and accepts overrides" do
    services = described_class.null(reviewer: "ana")

    expect(services.source.collections).to eq([])
    expect(services.run_log.list).to eq([])
    expect(services.reviewer).to eq("ana")
    expect(services.recompiler.call("text", section_id: "s")).to eq(Dry::Monads::Success("s"))
    expect(services.run_id.call).to match(/\A\h{8}-/)
    expect(services.terminal_host).to be_a(SFL::Core::Ports::Null::TerminalHost)
    expect(services.run_models).to be_nil
    expect(services.spawner.call(["true"], env: {}, name: "x")).to eq(File::NULL)
  end
end
