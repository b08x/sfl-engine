# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe SFL::TUI::App do
  let(:boot) { TUISpecSupport.boot_result }

  describe ".build" do
    it "injects the given boot and logger without ever calling SFL::Boot" do
      logger = SFL::Core::Ports::Null::Logger.new
      allow(SFL::Boot).to receive(:call)

      context = described_class.build(boot:, logger:)

      expect(context).to be_a(SFL::TUI::AppContext)
      expect(context.boot).to be(boot)
      expect(context.logger).to be(logger)
      expect(SFL::Boot).not_to have_received(:call)
    end

    # Never a StderrLogger: a background $stderr write lands inside the
    # rendered alt-screen frame and desynchronises the renderer.
    it "defaults to a JournaldLogger tagged sfl.tui" do
      allow(SFL::Core::Ports::JournaldLogger).to receive(:new).and_call_original

      context = described_class.build(boot:)

      expect(SFL::Core::Ports::JournaldLogger).to have_received(:new).with(progname: "sfl.tui")
      expect(context.logger).to be_a(SFL::Core::Ports::JournaldLogger)
    end

    it "falls back to AppContext's defaults when winsize raises on a detached terminal" do
      console = instance_double(IO)
      allow(IO).to receive(:console).and_return(console)
      allow(console).to receive(:winsize).and_raise(Errno::ENOTTY)

      context = described_class.build(boot:, logger: SFL::Core::Ports::Null::Logger.new)

      expect([context.width, context.height])
        .to eq([SFL::TUI::AppContext::DEFAULT_WIDTH, SFL::TUI::AppContext::DEFAULT_HEIGHT])
    end

    it "falls back to the defaults when there is no console at all (piped stdout)" do
      allow(IO).to receive(:console).and_return(nil)

      context = described_class.build(boot:, logger: SFL::Core::Ports::Null::Logger.new)

      expect([context.width, context.height])
        .to eq([SFL::TUI::AppContext::DEFAULT_WIDTH, SFL::TUI::AppContext::DEFAULT_HEIGHT])
    end

    it "takes the terminal size from winsize when the console reports one" do
      console = instance_double(IO, winsize: [50, 160])
      allow(IO).to receive(:console).and_return(console)

      context = described_class.build(boot:, logger: SFL::Core::Ports::Null::Logger.new)

      expect([context.width, context.height]).to eq([160, 50])
    end
  end

  describe ".program" do
    it "builds the root model closing over the context" do
      context = TUISpecSupport.context
      program = described_class.program(context)

      expect(program).to be_a(SFL::TUI::Program)
      expect(program.context).to be(context)
    end
  end
end
