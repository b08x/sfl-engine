# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe SFL::TUI::AppContext do
  subject(:context) { TUISpecSupport.context(width: 120, height: 40) }

  it "exposes the six Boot fields this Boot call populates and leaves the LLM ones nil" do
    expect(context.boot.spacy_model).to eq("en_core_web_sm")
    expect(context.boot.pass1_command).to eq(["python3"])
    expect(context.boot.llm_config).to be_nil
    expect(context.boot.embedder).to be_nil
    expect(context.boot.classifier).to be_nil
  end

  it "defaults its dimensions when none are given" do
    bare = described_class.new(boot: TUISpecSupport.boot_result, logger: SFL::Core::Ports::Null::Logger.new)

    expect([bare.width, bare.height]).to eq([described_class::DEFAULT_WIDTH, described_class::DEFAULT_HEIGHT])
  end

  it "falls back to the defaults when the first WindowSizeMessage reports 0x0" do
    zeroed = described_class.new(
      boot: TUISpecSupport.boot_result,
      logger: SFL::Core::Ports::Null::Logger.new,
      width: 0,
      height: 0
    )

    expect([zeroed.width, zeroed.height]).to eq([described_class::DEFAULT_WIDTH, described_class::DEFAULT_HEIGHT])
  end

  it "returns a resized copy rather than mutating" do
    resized = context.with_size(width: 200, height: 60)

    expect([resized.width, resized.height]).to eq([200, 60])
    expect([context.width, context.height]).to eq([120, 40])
  end

  it "ignores a non-positive resize instead of propagating a zero into the layout" do
    expect(context.with_size(width: 0, height: -3)).to have_attributes(width: 120, height: 40)
  end
end
