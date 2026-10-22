# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe SFL::TUI::EventLoop do
  let(:frames) { [] }

  def run_with(keys, services: SFL::TUI::Services.null(source: TUISpecSupport.source))
    queue = keys.map { |key| key && TUISpecSupport.key(key) }
    described_class.new(services:, draw: -> (state) { frames << state }, next_message: -> { queue.shift }).run
  end

  it "runs the first load, handles keys and stops on q" do
    final = run_with([nil, "2", "q"])

    expect(final.quit).to be(true)
    expect(final.active).to eq(1)
    expect(final.tabs.first.tree.roots).to eq(["c:1", "c:2"])
    expect(frames).not_to be_empty
  end

  it "runs the commands an update returns and feeds their messages back" do
    final = run_with(%w[down enter down q])

    expect(final.tabs.first.tree.loaded?("s:paper.md#intro")).to be(true)
  end

  it "keeps running when a command fails" do
    broken = SFL::Core::Ports::Fake::BrowseSource.new
    allow(broken).to receive(:collections).and_raise(SFL::Error, "db down")

    final = run_with(["q"], services: SFL::TUI::Services.null(source: broken))

    expect(final.status).to eq("collections: SFL::Error: db down")
    expect(final.error).to be(true)
    expect(final.tabs.first.load_error).to eq("SFL::Error: db down")
  end
end
