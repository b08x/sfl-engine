# frozen_string_literal: true

module SFL
  module TUI
    module Browse
      # Row labels for the tree and clause panes.
      module Rows
        extend self

        MARKS = { full: "[x]", partial: "[~]", none: "[ ]" }.freeze
        CONTENT_BADGE = " [R]"
        ANNOTATION_BADGE = "[A] "

        # @return [String] e.g. `    ▾ [~] Heading [R]`
        def tree_label(state, node)
          indent = "  " * node.depth
          "#{indent}#{expander(state, node)}#{mark(state, node)} #{node.label}#{badge(state, node)}"
        end

        # @return [String] e.g. `[x] [A] The clause text`
        def clause_label(state, node)
          badge = state.reviews.annotation_pending?(node.data[:id]) ? ANNOTATION_BADGE : ""
          "#{mark(state, node)} #{badge}#{node.label.tr("\n", ' ')}"
        end

        private def mark(state, node) = MARKS.fetch(state.selection.state(state.tree, node.id))

        private def expander(state, node)
          return "  " if state.tree.children(node.id).none? { |id| state.tree.node(id).kind != :clause }

          state.expanded.include?(node.id) ? "▾ " : "▸ "
        end

        private def badge(state, node)
          (node.kind == :section && state.reviews.pending?(node.data[:section_id])) ? CONTENT_BADGE : ""
        end
      end
    end
  end
end
