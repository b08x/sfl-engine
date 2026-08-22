# frozen_string_literal: true

require_relative "../spec_helper"

# One file for all four shells: in Phase 1 they differ only in title and pane
# proportions, so four near-identical spec files would be duplication, not
# coverage. They split when each grows real collaborators.
RSpec.describe SFL::TUI::Workspaces::Base do
  let(:context) { TUISpecSupport.context(width: 120, height: 40) }

  SFL::TUI::Program::WORKSPACE_CLASSES.each do |workspace_class|
    describe workspace_class do
      subject(:workspace) { workspace_class.new }

      it "has a tab title" do
        expect(workspace.title).to be_a(String).and(be_truthy)
      end

      it "initializes to itself with no command" do
        expect(workspace.init(context)).to eq([workspace, nil])
      end

      it "accepts an unhandled message without acting on it" do
        model, command = workspace.update(Bubbletea::WindowSizeMessage.new(width: 80, height: 24), context)

        expect(model).to be(workspace)
        expect(command).to be_nil
      end

      it "renders within the body area the root Program leaves it" do
        rendered = workspace.view(context)

        expect(Lipgloss.width(rendered)).to be <= context.width
        expect(Lipgloss.height(rendered)).to eq(SFL::TUI::Layout.body_height(context))
      end
    end
  end

  it "refuses to render an abstract workspace" do
    expect { described_class.new.view(context) }.to raise_error(NotImplementedError)
  end
end
