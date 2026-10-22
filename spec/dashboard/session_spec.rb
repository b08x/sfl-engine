# frozen_string_literal: true

require "spec_helper"
require "delegate"
require "ratatui_ruby"
require "timeout"

RSpec.describe SFL::Dashboard::Session do
  # Draws into ratatui's test terminal, on the thread that calls #run, as
  # ratatui requires. Each poll takes the next key; a Proc entry stays at the
  # head of the queue and answers every poll with what it returns.
  let(:fake_tui) do
    Class.new(SimpleDelegator) do
      def initialize(tui, keys)
        super(tui)
        @keys = keys
      end

      def poll_event(timeout:) # rubocop:disable Lint/UnusedMethodArgument -- TUI#poll_event signature
        sleep 0.001
        @keys.first.is_a?(Proc) ? @keys.first.call : @keys.shift
      end
    end
  end

  let(:terminal) do
    tui_class = fake_tui
    Class.new do
      attr_reader :screen

      define_method(:initialize) { |keys| @keys = keys }

      define_method(:run) do |&block|
        RatatuiRuby.init_test_terminal(110, 30)
        block.call(tui_class.new(RatatuiRuby::TUI.new, @keys))
      ensure
        @screen = RatatuiRuby.get_buffer_content
        RatatuiRuby.restore_terminal
      end
    end
  end

  let(:ctrl_c) { RatatuiRuby::Event::Key.new(code: "c", modifiers: ["ctrl"]) }
  let(:any_key) { RatatuiRuby::Event::Key.new(code: "q") }
  let(:stop_flag) { SFL::CLI::StopFlag.new }
  let(:board) do
    SFL::Dashboard::Board.new(SFL::Dashboard::State.initial(run_id: "r1", kind: "annotate", collection: "c", models: [],
      documents: 1, now: Time.at(0)))
  end

  def wait_for(seconds = 2)
    deadline = Time.now + seconds
    sleep 0.005 until yield || Time.now > deadline
  end

  def session(term, abort: -> {}, hold: true)
    described_class.new(board:, stop_flag:, terminal: term, clock: -> { Time.at(5) }, abort:, hold:)
  end

  it "maps the first Ctrl-C to the stop flag and shows the outcome on the final screen (fact 51)" do
    returned = false
    term = terminal.new([ctrl_c, -> { any_key if returned }])
    dashboard = session(term)

    value = Timeout.timeout(5) do
      dashboard.run do
        wait_for { stop_flag.stopped? }
        dashboard.sink(SFL::Core::Ports::Null::ProgressSink.new).finish(status: "interrupted")
        returned = true
        :done
      end
    end

    expect(value).to eq(:done)
    expect(stop_flag.stopped?).to be(true)
    expect(board.state.stopping).to be(true)
    expect(term.screen).to include("sfl annotate · interrupted", "press any key to exit")
  end

  it "quits at once on the second Ctrl-C" do
    aborted = false
    term = terminal.new([nil, ctrl_c, any_key, ctrl_c])

    session(term, abort: -> { aborted = true }, hold: false).run { wait_for { aborted } }

    expect(aborted).to be(true)
  end

  it "captures stray output into the log while drawn and restores stdout and stderr after" do
    out = $stdout
    term = terminal.new([])

    session(term, hold: false).run do
      puts "stray line" # rubocop:disable RSpec/Output -- the output under test is captured, not printed
      warn "stray warning"
    end

    expect(board.state.log).to eq(["stray line", "stray warning"])
    expect($stdout).to be(out)
  end

  it "restores the terminal and re-raises when the run fails" do
    term = terminal.new([])

    expect { Timeout.timeout(5) { session(term).run { raise ArgumentError, "boom" } } }.to raise_error(ArgumentError, "boom")
    expect(term.screen).to include("sfl annotate · running")
  end

  it "builds the log target and the progress sink over its board" do
    dashboard = session(terminal.new([]))
    dashboard.logger(level: 0).debug("hello")
    dashboard.sink(SFL::Core::Ports::Null::ProgressSink.new).start(3)

    expect(board.state).to have_attributes(log: ["[DEBUG] hello"], sections_total: 3)
    expect(dashboard.board).to be(board)
  end
end
