# frozen_string_literal: true

require "lipgloss"

module SFL
  module TUI
    module Workspaces
      # The workspace sub-model contract (docs/tui-implementation-plan.md §3).
      #
      # Deliberately NOT bubbletea-ruby's own Model contract: the root Program
      # is the only real Bubbletea::Model in the app (init/0, update/1, view/0,
      # closing over its AppContext). Workspaces take the context explicitly —
      # init/1, update/2, view/1 — because there is exactly one context and
      # copying it into four sub-models would mean four places to keep in sync
      # on every WindowSizeMessage.
      #
      # Sub-models return a NEW instance rather than mutating. `bubbles`' own
      # sub-models do the opposite (they mutate in place and return [self, cmd])
      # — the wrapper that first embeds a Bubbles::List or Bubbles::Viewport is
      # where the two conventions meet, and it is that wrapper's job to
      # reconcile them rather than to leak in-place mutation upward.
      #
      # Phase 1 subclasses are shells: they hold no state, accept every message
      # without acting on it, and paint their pane skeleton only.
      class Base
        # @return [String] tab label
        def title = raise(NotImplementedError, "#{self.class}#title")

        # @param _context [AppContext]
        # @return [Array(Base, Bubbletea::Command, nil)]
        def init(_context) = [self, nil]

        # @param _message [Bubbletea::Message]
        # @param _context [AppContext]
        # @return [Array(Base, Bubbletea::Command, nil)] a SINGLE command or nil,
        #   never an Array of commands — combine with Bubbletea.batch/sequence.
        def update(_message, _context) = [self, nil]

        # @param context [AppContext]
        # @return [String] must fit context.width x Layout.body_height(context)
        def view(context) = raise(NotImplementedError, "#{self.class}#view(#{context.class})")

        # Renders one bordered pane of the given total size.
        private def pane(title, body, width:, height:, active: true)
          Theme.pane(width:, height:, active:).render("#{Theme.pane_title(title)}\n#{body}")
        end

        private def row(*panes) = Lipgloss.join_horizontal(Lipgloss::Position::TOP, *panes)

        private def stack(*panes) = Lipgloss.join_vertical(Lipgloss::Position::LEFT, *panes)

        # Every Phase 1 pane says what it will hold, not "TODO" — the shell is
        # the layout contract the later phase fills in.
        private def pending(text) = Theme.placeholder("#{text}\n\n(no live data — Phase 1 skeleton)")
      end
    end
  end
end
