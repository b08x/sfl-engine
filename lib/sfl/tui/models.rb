# frozen_string_literal: true

module SFL
  module TUI
    # The Models tab: every task with its effective provider and model and
    # where it came from (env, db or default) on the left, and the listed
    # models with the capability the selected task needs on the right.
    # Enter on a task moves to its models; Enter on a model saves it to
    # `task_models`. A task set by an env var is locked. `r` refreshes the
    # `models` table from the catalogs.
    module Models
      TITLE = "Models"
      HELP = "↑/↓ move · enter choose · esc back · r refresh"

      # - `focus`: :tasks or :models
      # - `notice`: the last assign or refresh outcome
      State = Data.define(:tasks, :models, :cursor, :model_cursor, :focus, :notice) do
        def task = tasks[cursor]

        def candidates = task ? Rows.candidates(models, task[:capability]) : []
      end

      extend self

      def initial = State.new(tasks: [], models: [], cursor: 0, model_cursor: 0, focus: :tasks, notice: nil)

      # @return [Proc] the first load
      def init(services) = load(services)

      def handles?(message) = message.is_a?(Messages::ModelsLoaded)

      def capturing?(_state) = false

      def help(_state) = HELP

      # @return [String, nil] the last notice, else a count
      def status(state)
        return state.notice if state.notice

        "#{state.tasks.size} tasks, #{state.models.size} models" unless state.tasks.empty?
      end

      # @return [Array(State, Proc|nil)]
      def update(state, message, services)
        case message
        when Messages::ModelsLoaded then [loaded(state, message), nil]
        when Messages::Key then key(state, message.key, services)
        else [state, nil]
        end
      end

      # @return [Proc] -> Messages::ModelsLoaded
      def load(services, notice: nil)
        SafeCommand.wrap(source: :models, logger: services.logger) { loaded_message(services, notice) }
      end

      # @return [Proc] saves the assignment, then reloads
      def assign(services, task, model)
        SafeCommand.wrap(source: :models, logger: services.logger) do
          services.model_store.assign(task[:task], provider: model[:provider], model_id: model[:model_id])
          services.logger.info("task model assigned", task: task[:task], provider: model[:provider], model: model[:model_id])
          loaded_message(services, "#{task[:task]} -> #{model[:provider]}/#{model[:model_id]}")
        end
      end

      # @return [Proc] refreshes every catalog, then reloads
      def refresh(services)
        SafeCommand.wrap(source: :models, logger: services.logger) do
          loaded_message(services, services.model_refresher.call.join(" · "))
        end
      end

      def loaded_message(services, notice)
        models = services.model_store.list
        Messages::ModelsLoaded.new(tasks: Rows.tasks(services.model_resolver.resolve, models), models:, notice:)
      end

      def loaded(state, message)
        state = state.with(tasks: message.tasks, models: message.models, notice: message.notice || state.notice)
        state.with(cursor: clamp(state.cursor, state.tasks), model_cursor: clamp(state.model_cursor, state.candidates))
      end

      def key(state, key, services)
        return [state, refresh(services)] if key == "r"

        (state.focus == :models) ? model_key(state, key, services) : task_key(state, key)
      end

      private def task_key(state, key)
        case key
        when "up", "k" then [state.with(cursor: clamp(state.cursor - 1, state.tasks)), nil]
        when "down", "j" then [state.with(cursor: clamp(state.cursor + 1, state.tasks)), nil]
        when "enter" then [choose(state), nil]
        else [state, nil]
        end
      end

      private def choose(state)
        return state unless state.task
        return state.with(notice: "#{state.task[:task]} is locked by #{state.task[:env_var]}") if Rows.locked?(state.task)

        current = state.candidates.index { |row| [row[:provider], row[:model_id]] == [state.task[:provider], state.task[:model]] }
        state.with(focus: :models, model_cursor: current || 0)
      end

      private def model_key(state, key, services)
        case key
        when "up", "k" then [state.with(model_cursor: clamp(state.model_cursor - 1, state.candidates)), nil]
        when "down", "j" then [state.with(model_cursor: clamp(state.model_cursor + 1, state.candidates)), nil]
        when "esc" then [state.with(focus: :tasks), nil]
        when "enter" then pick(state, services)
        else [state, nil]
        end
      end

      private def pick(state, services)
        model = state.candidates[state.model_cursor]
        return [state, nil] unless model

        [state.with(focus: :tasks), assign(services, state.task, model)]
      end

      private def clamp(index, rows) = index.clamp(0, [rows.size - 1, 0].max)

      def render(state, frame, area, tui) = View.render(state, frame, area, tui)
    end
  end
end
