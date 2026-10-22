# frozen_string_literal: true

module SFL
  module TUI
    # The root of the TUI: tab container state, a pure update, and the
    # frame layout (tab bar, active tab, status line, help line).
    #
    # Tabs are modules answering one protocol (see Browse). Adding a tab is
    # adding a module to TABS.
    module Program
      TABS = [Browse, Search, Runs, Models].freeze
      QUIT_KEYS = %w[ctrl_c q].freeze
      TAB_KEYS = TABS.each_index.to_h { |index| [(index + 1).to_s, index] }.freeze
      LAUNCH_KEY = "i"
      GLOBAL_HELP = "1-#{TABS.size} switch tab · i ingest · q quit".freeze
      # The help line wraps onto a second row on narrow terminals.
      HELP_ROWS = 2

      # - `tabs`: one state per entry in TABS
      # - `status`: the latest notice, or the first failure since one; nil for none
      # - `more_errors`: failures that arrived after the shown one
      # - `launcher`: the ingest launcher's Launcher::State while it is open
      State = Data.define(:tabs, :active, :status, :error, :more_errors, :quit, :launcher) do
        def active_tab = TABS.fetch(active)
        def active_state = tabs.fetch(active)
      end

      extend self

      def initial
        State.new(tabs: TABS.map(&:initial), active: 0, status: nil, error: false, more_errors: 0, quit: false, launcher: nil)
      end

      # @return [Array<Proc>] each tab's first command
      def init(services) = TABS.filter_map { |tab| tab.init(services) }

      # @param message [Object] a Messages::* value
      # @return [Array(State, Proc|nil)]
      def update(state, message, services)
        case message
        when Messages::Key then key(state, message.key, services)
        when Messages::Failed then failed(state, message, services)
        when Messages::Status then [notice(state, message.text), nil]
        when Messages::Exported then [notice(state, "exported #{message.count} clauses to #{message.path}"), nil]
        when Messages::Launched then launched(state, message, services)
        else route(state, message, services)
        end
      end

      def key(state, key, services)
        return [state.with(quit: true), nil] if key == "ctrl_c"
        return launcher_key(state, key, services) if state.launcher

        return delegate(state, state.active, Messages::Key.new(key), services) if state.active_tab.capturing?(state.active_state)

        global_key(state, key, services)
      end

      # Keys the container claims when the active tab is not capturing text.
      private def global_key(state, key, services)
        return [state.with(quit: true), nil] if QUIT_KEYS.include?(key)
        return [state.with(launcher: Launcher.open(collections(state))), nil] if key == LAUNCH_KEY

        index = TAB_KEYS[key]
        return [state.with(active: index), nil] if index

        delegate(state, state.active, Messages::Key.new(key), services)
      end

      # While the launcher is open every key but ctrl_c belongs to it.
      def launcher_key(state, key, services)
        launcher, request = Launcher.update(state.launcher, key)
        [state.with(launcher:), request && Launcher::Commands.start(services, request)]
      end

      # A notice replaces the status and clears any failures.
      def notice(state, text) = state.with(status: text, error: false, more_errors: 0)

      # The first failure stays on the status line and later ones are
      # counted, so init's three loads cannot hide each other. The tab that
      # handles failures (Browse, for its own load) also receives it.
      def failed(state, message, services)
        state = state.error ? state.with(more_errors: state.more_errors + 1) : state.with(status: message.to_s, error: true)
        index = TABS.index { |tab| tab.handles?(message) }
        index ? delegate(state, index, message, services) : [state, nil]
      end

      # A detached ingest is followed on the Runs tab, which reloads now.
      def launched(state, message, services)
        state = notice(state, message.text)
        return [state, nil] unless message.detached

        [state.with(active: TABS.index(Runs)), Runs.load(services)]
      end

      # @return [Array<String>] collection names Browse has loaded
      def collections(state)
        tree = state.tabs.fetch(TABS.index(Browse)).tree
        tree.roots.map { |id| tree.node(id).label }
      end

      # Results go to the tab that handles them; a Reviewed notice also
      # reaches the status line.
      def route(state, message, services)
        index = TABS.index { |tab| tab.handles?(message) }
        return [state, nil] unless index

        state = notice(state, message.text) if message.is_a?(Messages::Reviewed)
        delegate(state, index, message, services)
      end

      def delegate(state, index, message, services)
        tab_state, command = TABS.fetch(index).update(state.tabs.fetch(index), message, services)
        tabs = state.tabs.dup.tap { |all| all[index] = tab_state }
        [state.with(tabs:), command]
      end

      # @return [String] every key the active tab and the container accept
      def help(state)
        return "#{Launcher::HELP} · ctrl_c quit" if state.launcher

        "#{state.active_tab.help(state.active_state)} · #{GLOBAL_HELP}"
      end

      # @return [String] the tab's own status, then the latest notice and
      #   the count of failures it hides
      def status_line(state) = [state.active_tab.status(state.active_state), status_text(state)].compact.join(" | ")

      private def status_text(state)
        count = state.more_errors
        return state.status if count.zero?

        "#{state.status} (+#{count} more error#{'s' unless count == 1})"
      end

      # Cuts text to +width+ columns, ending in an ellipsis when cut. The
      # full failure text is in the log (SafeCommand logs every failure).
      # @return [String]
      def fit(text, width)
        return text if text.length <= width

        width.positive? ? "#{text[0, width - 1]}…" : ""
      end

      # @param frame [RatatuiRuby::Frame]
      # @param tui [RatatuiRuby::TUI]
      def render(state, frame, tui)
        tabs_area, body, status_area, help_area = tui.layout_split(frame.area, direction: :vertical,
          constraints: [tui.constraint_length(1), tui.constraint_fill(1), tui.constraint_length(1), tui.constraint_length(HELP_ROWS)])
        titles = TABS.each_with_index.map { |tab, index| "#{index + 1} #{tab::TITLE}" }
        frame.render_widget(tui.tabs(titles:, selected_index: state.active, highlight_style: tui.style(fg: :cyan, modifiers: [:bold])),
          tabs_area)
        state.active_tab.render(state.active_state, frame, body, tui)
        Launcher::View.render(state.launcher, frame, body, tui) if state.launcher
        frame.render_widget(tui.paragraph(text: fit(status_line(state), status_area.width), style: tui.style(fg: state.error ? :red : :reset)),
          status_area)
        frame.render_widget(tui.paragraph(text: help(state), wrap: true, style: tui.style(fg: :dark_gray)), help_area)
      end
    end
  end
end
