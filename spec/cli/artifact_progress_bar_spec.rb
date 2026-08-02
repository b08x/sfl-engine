# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe SFL::CLI::ArtifactProgressBar do
  subject(:progress_bar) { described_class.new }

  # See TurnProgressBar's spec for why #tty? must be stubbed true here.
  let(:output) do
    StringIO.new.tap { |io| io.define_singleton_method(:tty?) { true } }
  end

  before do
    allow(TTY::ProgressBar).to receive(:new).and_wrap_original do |original, format, opts|
      original.call(format, opts.merge(output:))
    end
  end

  it "creates the bar lazily on the first #advance, sized to the run's total, and logs the artifact" do
    progress_bar.advance(artifact_id: 1, total: 4, title: "Overview", source_file: "/docs/readme.md")

    expect(output.string).to include("1/4 [readme.md] Overview")
  end

  it "reuses the same bar across multiple #advance calls rather than recreating it" do
    progress_bar.advance(artifact_id: 1, total: 4, title: "Overview", source_file: "/docs/readme.md")
    first_bar = progress_bar.instance_variable_get(:@bar)

    progress_bar.advance(artifact_id: 2, total: 4, title: "Setup", source_file: "/docs/setup.md")

    expect(progress_bar.instance_variable_get(:@bar)).to equal(first_bar)
    expect(output.string).to include("2/4 [setup.md] Setup")
  end
end
