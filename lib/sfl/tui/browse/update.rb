# frozen_string_literal: true

module SFL
  module TUI
    module Browse
      # Pure state transitions for the Browse tab. Returns the new state and
      # at most one command; never performs I/O itself.
      module Update
        extend self

        EXPORT_FORMATS = { "j" => :jsonl, "m" => :markdown }.freeze
        DECISIONS = { "A" => "approve", "R" => "reject" }.freeze
        # Keys handled outside the export overlay, mapped to the transition
        # each one runs. Keys not listed fall through to #review_key.
        KEY_ACTIONS = {
          %w[up k] => :cursor_up,
          %w[down j] => :cursor_down,
          %w[tab] => :switch_focus,
          %w[enter right l] => :expand,
          [" "] => :select_focused,
          %w[a] => :select_all,
          %w[esc] => :clear_selection,
          %w[f] => :next_filter,
          %w[e] => :open_export,
          %w[r] => :reload,
        }.flat_map { |keys, action| keys.map { |key| [key, action] } }.to_h.freeze

        # @return [Array(State, Proc|nil)]
        def call(state, message, services)
          case message
          when Messages::Key then key(state, message.key, services)
          when Messages::BrowseLoaded then loaded(state, message, services)
          when Messages::ClausesLoaded then clauses_loaded(state, message)
          when Messages::Reviewed then [state, Commands.load(services)]
          when Messages::Failed then [load_failed(state, message), nil]
          else [state, nil]
          end
        end

        private def key(state, key, services)
          return overlay_key(state, key, services) if state.overlay

          action = KEY_ACTIONS[key]
          action ? __send__(action, state, services) : review_key(state, key, services)
        end

        private def cursor_up(state, services) = move(state, -1, services)
        private def cursor_down(state, services) = move(state, 1, services)
        private def switch_focus(state, _services) = [state.with(focus: (state.focus == :tree) ? :clauses : :tree, clause_cursor: 0), nil]
        private def expand(state, _services) = [toggle_expanded(state), nil]
        private def select_focused(state, _services) = [toggle_selection(state), nil]
        private def select_all(state, _services) = [state.with(selection: state.selection.select_all(state.tree, state.level_ids)), nil]
        private def clear_selection(state, _services) = [state.with(selection: state.selection.clear), nil]
        private def next_filter(state, _services) = [state.with(filter: StatusFilter.next(state.filter), cursor: 0, clause_cursor: 0), nil]
        private def open_export(state, _services) = [state.selection.empty? ? state : state.with(overlay: :export), nil]
        private def reload(state, services) = [state, Commands.load(services)]

        private def review_key(state, key, services)
          item = state.review_item
          return [state, nil] unless item

          case key
          when *DECISIONS.keys then pending_only(state, item) { Commands.decide(services, item, DECISIONS.fetch(key)) }
          when "E" then pending_only(state, item) { Commands.edit(services, item, collection(state)) }
          when "o" then [state, (item[:modality] == "image") ? Commands.open(services, item) : nil]
          else [state, nil]
          end
        end

        private def pending_only(state, item) = [state, (item[:status] == "pending") ? yield : nil]

        private def overlay_key(state, key, services)
          format = EXPORT_FORMATS[key]
          return [state.with(overlay: nil), Commands.export(services, state.picks, format)] if format
          return [state.with(overlay: nil), nil] if key == "esc"

          [state, nil]
        end

        private def move(state, delta, services)
          return [state.with(clause_cursor: clamp(state.clause_cursor + delta, state.clause_rows.size)), nil] if state.focus == :clauses

          moved = state.with(cursor: clamp(state.cursor + delta, state.rows.size), clause_cursor: 0)
          [moved, clauses_command(moved, services)]
        end

        # Loads the focused section's clauses the first time it is focused.
        private def clauses_command(state, services)
          section = state.focused_section
          return nil if section.nil? || state.tree.loaded?(section.id)

          Commands.load_clauses(services, section.data[:section_id])
        end

        private def toggle_expanded(state)
          row = state.focused_row
          return state if row.nil? || state.tree.children(row.id).none? { |id| state.tree.node(id).kind != :clause }

          expanded = state.expanded.include?(row.id) ? state.expanded - [row.id] : state.expanded | [row.id]
          state.with(expanded:)
        end

        private def toggle_selection(state)
          node = state.focused_node
          node ? state.with(selection: state.selection.toggle(state.tree, node.id)) : state
        end

        private def loaded(state, message, services)
          expanded = state.expanded.empty? ? Set.new(message.tree.roots) : state.expanded
          ids = state.selection.ids.select { |id| message.tree.node(id) }
          next_state = state.with(tree: message.tree, reviews: message.reviews, expanded:, selection: Selection.new(ids), load_error: nil)
          next_state = next_state.with(cursor: clamp(next_state.cursor, next_state.rows.size))
          [next_state, clauses_command(next_state, services)]
        end

        private def load_failed(state, message) = (message.source == Commands::LOAD_SOURCE) ? state.with(load_error: message.detail) : state

        private def clauses_loaded(state, message)
          section_id = Browse.section_node(message.section_id)
          return [state, nil] unless state.tree.node(section_id)

          tree = state.tree.with_clauses(message.section_id, message.clauses)
          [state.with(tree:, selection: state.selection.absorb(tree, section_id)), nil]
        end

        private def collection(state)
          section = state.focused_section
          section && state.tree.collection_of(section.id)&.label
        end

        private def clamp(value, size) = size.zero? ? 0 : value.clamp(0, size - 1)
      end
    end
  end
end
