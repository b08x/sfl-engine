# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe SFL::TUI::AppContext do
  it "bundles the boot result, logger and services" do
    services = SFL::TUI::Services.null
    logger = SFL::Core::Ports::Null::Logger.new
    context = described_class.new(boot: :boot, logger:, services:)

    expect(context).to have_attributes(boot: :boot, logger:, services:)
  end
end
