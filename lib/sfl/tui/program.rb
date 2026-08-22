# frozen_string_literal: true

require "bubbletea"
require "lipgloss"

module SFL
  module TUI
    # The root MVU model: owns tab state, routes Alt+1..4, and forwards every
    # other message to the active workspace.
    #
    # This is the ONLY Bubbletea::Model in the app, and it implements
    # bubbletea-ruby's real arities — init/0, update/1, view/0. The AppContext
    # is closed over, not passed in (docs/tui-implementation-plan.md §3/§4
    # describe a context-passing variant of these methods; that is not the API
    # the gem actually has, and building against it would fail at the first
    # message).
    #
    # Every method returns a SINGLE Bubbletea::Command or nil — never an Array.
    # Multiple commands combine through Bubbletea.batch/Bubbletea.sequence.
    class Program
      include Bubbletea::Model

      WORKSPACE_CLASSES = [
        Workspaces::QueryConsole,
        Workspaces::ReviewQueue,
        Workspaces::CorpusBrowser,
        Workspaces::Board,
      ].freeze

      # Ctrl+C reaches the model ONLY as a KeyMessage — bubbletea-ruby installs
      # no SIGINT handler. A model that does not map it to Bubbletea.quit stays
      # alive with the terminal stranded in raw mode inside the alt screen, and
      # the user's only recourse is another terminal. It is mapped
      # unconditionally, before any workspace delegation, for that reason.
      QUIT_KEYS = ["ctrl+c", "q"].freeze

      TAB_KEYS = (1..(WORKSPACE_CLASSES.size)).to_h { |index| ["alt+#{index}", index - 1] }.freeze

      attr_reader :context, :workspaces, :active_index, :error

      def initialize(context:, workspaces: nil, active_index: 0, error: nil)
        @context = context
        @workspaces = workspaces || WORKSPACE_CLASSES.map(&:new)
        @active_index = active_index
        @error = error
      end

      def init
        initialized, commands = init_workspaces
        [with(workspaces: initialized), batch(commands)]
      end

      def update(message)
        case message
        when Bubbletea::WindowSizeMessage then [resized(message), nil]
        when Bubbletea::KeyMessage then handle_key(message)
        when Messages::Failed then [with(error: message.to_s), nil]
        else delegate(message)
        end
      end

      def view
        Lipgloss.join_vertical(
          Lipgloss::Position::LEFT,
          clamp(tab_bar),
          active_workspace.view(context),
          clamp(status_bar)
        )
      end

      def active_workspace = workspaces.fetch(active_index)

      private def handle_key(message)
        key = message.to_s
        return [self, Bubbletea.quit] if QUIT_KEYS.include?(key)

        index = TAB_KEYS[key]
        return [switch_to(index), nil] if index

        delegate(message)
      end

      # Failure states are cleared on a tab switch: an error belongs to the
      # pane that produced it, and carrying it across the whole chrome would
      # make an unrelated workspace look broken.
      private def switch_to(index)
        return self if index == active_index

        context.logger.debug { "tui tab -> #{workspaces.fetch(index).title}" }
        with(active_index: index, error: nil)
      end

      private def resized(message)
        with(context: context.with_size(width: message.width, height: message.height))
      end

      private def delegate(message)
        workspace, command = active_workspace.update(message, context)
        replaced = workspaces.each_with_index.map { |existing, index| (index == active_index) ? workspace : existing }

        [with(workspaces: replaced), command]
      end

      private def init_workspaces
        commands = []
        initialized = workspaces.map do |workspace|
          model, command = workspace.init(context)
          commands << command if command
          model
        end
        [initialized, commands]
      end

      private def batch(commands)
        case commands.size
        when 0 then nil
        when 1 then commands.first
        else Bubbletea.batch(*commands)
        end
      end

      private def tab_bar
        Lipgloss.join_horizontal(
          Lipgloss::Position::TOP,
          *workspaces.each_with_index.map do |workspace, index|
            Theme.tab("#{index + 1} #{workspace.title}", active: index == active_index)
          end
        )
      end

      private def status_bar
        return Theme.error("error · #{error}") if error

        Theme.status("alt+1..#{workspaces.size} switch workspace · q / ctrl+c quit")
      end

      # The chrome rows are the only part of the frame not built from Layout's
      # arithmetic — four full tab labels are wider than a narrow terminal, and
      # a tab bar that wraps pushes the whole body down a row and desyncs the
      # renderer. Truncating is the lesser evil; the workspace panes below are
      # already sized to fit exactly.
      #
      # max_height(1) is the structural half of that invariant, and it is here
      # rather than at each caller on purpose: the status bar renders arbitrary
      # failure detail, and one future caller that forgets to sanitise would
      # otherwise silently reintroduce a wrapped chrome row. Messages::Failed
      # collapses whitespace as well, so the clamp is a backstop, not the only
      # line of defence.
      private def clamp(line) = Lipgloss::Style.new.max_width(context.width).max_height(1).render(line)

      private def with(context: @context, workspaces: @workspaces, active_index: @active_index, error: @error)
        self.class.new(context:, workspaces:, active_index:, error:)
      end
    end
  end
end
