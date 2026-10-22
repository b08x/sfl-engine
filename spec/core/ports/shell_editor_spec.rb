# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::ShellEditor do
  it "runs the editor command on a temp file holding the text, inside suspend, and returns the edited file" do
    calls = []
    suspended = []
    runner = lambda do |*argv|
      calls << argv
      File.write(argv.last, "#{File.read(argv.last)} edited")
      true
    end
    suspend = -> (&block) { suspended << :in; block.call }

    edited = described_class.new(command: "code -w", suspend:, runner:).edit("draft")

    expect(edited).to eq("draft edited")
    expect(calls.first.first(2)).to eq(["code", "-w"])
    expect(suspended).to eq([:in])
  end

  it "raises when the editor exits with an error" do
    editor = described_class.new(command: "false", runner: -> (*_argv) { false })

    expect { editor.edit("x") }.to raise_error(described_class::Error, /false/)
  end
end
