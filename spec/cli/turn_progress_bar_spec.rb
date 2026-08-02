# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe SFL::CLI::TurnProgressBar do
  subject(:progress_bar) { described_class.new }

  # TTY::ProgressBar silently no-ops on a non-tty output (per its own
  # "not a TTY, the bar will not render" contract) — a bare StringIO's
  # #tty? is false, so the bar needs one that claims to be a tty to
  # actually render anything for these specs to assert on.
  let(:output) do
    StringIO.new.tap { |io| io.define_singleton_method(:tty?) { true } }
  end

  before do
    allow(TTY::ProgressBar).to receive(:new).and_wrap_original do |original, format, opts|
      original.call(format, opts.merge(output:))
    end
  end

  it "creates the bar lazily on the first #start, sized to the run's total" do
    progress_bar.start(turn_id: 1, total: 3, speaker: "Human")

    expect(output.string).to include("1/3 (Human)...")
  end

  it "reuses the same bar across multiple #start calls rather than recreating it" do
    progress_bar.start(turn_id: 1, total: 3, speaker: "Human")
    first_bar = progress_bar.instance_variable_get(:@bar)

    progress_bar.start(turn_id: 2, total: 3, speaker: "Assistant")

    expect(progress_bar.instance_variable_get(:@bar)).to equal(first_bar)
  end

  it "#advance logs OK when nothing defaulted and advances the bar" do
    progress_bar.start(turn_id: 1, total: 2, speaker: "Human")

    progress_bar.advance(turn_id: 1, total: 2, speaker: "Human", elapsed: 1.23, clause_count: 5, defaulted: 0)

    expect(output.string).to include("1.23s [OK]")
  end

  it "#advance logs the defaulted count when Pass 2 fell back for any clauses" do
    progress_bar.start(turn_id: 1, total: 2, speaker: "Human")

    progress_bar.advance(turn_id: 1, total: 2, speaker: "Human", elapsed: 0.5, clause_count: 5, defaulted: 2)

    expect(output.string).to include("0.5s [2/5 DEFAULTED]")
  end
end
