# frozen_string_literal: true

module SFL
  module TUI
    module Browse
      # Browse tab state and the views derived from it. Never mutated:
      # update returns a copy through Data#with.
      #
      # - `focus`: :tree or :clauses, the pane the cursor keys move in
      # - `expanded`: node ids whose children are shown in the tree
      # - `overlay`: nil, or :export while the format choice is open
      # - `load_error`: why the last load failed, nil once one succeeds
      State = Data.define(:tree, :reviews, :selection, :expanded, :cursor, :clause_cursor, :focus, :filter, :overlay,
        :load_error) do
        # @return [State] an empty Browse with nothing loaded
        def self.initial
          new(tree: Tree.new, reviews: Reviews.new, selection: Selection.new, expanded: Set.new, cursor: 0,
            clause_cursor: 0, focus: :tree, filter: "all", overlay: nil, load_error: nil)
        end

        # @return [Array<Tree::Node>] collections, documents and sections shown in the tree pane
        def rows = tree.roots.flat_map { |id| visible(id) }

        # @return [Tree::Node, nil]
        def focused_row = rows[cursor]

        # @return [Tree::Node, nil] the section under the tree cursor
        def focused_section
          node = focused_row
          node if node&.kind == :section
        end

        # @return [Array<Tree::Node>] the focused section's clauses that pass the filter
        def clause_rows
          section = focused_section
          return [] unless section

          tree.clauses(section.id).select do |node|
            StatusFilter.match?(filter, reviews.clause_status(node.data[:id], section.data[:section_id]))
          end
        end

        # @return [Tree::Node, nil] the clause under the clause cursor, when that pane has focus
        def focused_clause = (focus == :clauses) ? clause_rows[clause_cursor] : nil

        # @return [Tree::Node, nil] the row Space acts on
        def focused_node = (focus == :clauses) ? focused_clause : focused_row

        # @return [Array<String>] ids at the focused row's level in the focused pane
        def level_ids
          return clause_rows.map(&:id) if focus == :clauses

          row = focused_row
          row ? peer_ids(row) : []
        end

        # @return [Hash, nil] the content-review item of the focused section
        def review_item
          section = focused_section
          section && reviews.item(section.data[:section_id])
        end

        # @return [Array<Export::SectionPick>] the selected sections, and
        #   sections with only some clauses selected, in corpus order
        def picks
          positions = {}
          tree.sections.filter_map do |node|
            clause_ids = chosen_clause_ids(node)
            next if clause_ids == []

            document = tree.document_of(node.id)
            positions[document.id] ||= positions.size
            pick(node, document, clause_ids, positions[document.id])
          end
        end

        # @return [Boolean] whether the node passes the status filter; a
        #   parent passes when any of its known descendants does
        def matches?(node)
          return true if filter == "all"

          case node.kind
          when :section then section_matches?(node)
          when :clause then clause_matches?(node)
          else descendant_matches?(node)
          end
        end

        private def section_matches?(node)
          StatusFilter.match?(filter, reviews.section_status(node.data[:section_id])) || descendant_matches?(node)
        end

        private def clause_matches?(node)
          StatusFilter.match?(filter, reviews.clause_status(node.data[:id], tree.node(node.parent_id).data[:section_id]))
        end

        private def descendant_matches?(node) = tree.children(node.id).any? { |child| matches?(tree.node(child)) }

        private def peer_ids(row) = rows.select { |node| node.kind == row.kind && node.depth == row.depth }.map(&:id)

        private def visible(id)
          node = tree.node(id)
          return [] if node.kind == :clause || !matches?(node)
          return [node] unless expanded.include?(id)

          [node, *tree.children(id).flat_map { |child| visible(child) }]
        end

        # nil for a wholly selected section, the selected clause ids for a
        # partly selected one, [] for one with nothing selected
        private def chosen_clause_ids(node)
          return nil if selection.ids.include?(node.id)

          tree.clauses(node.id).map(&:id).select { |id| selection.ids.include?(id) }.map { |id| tree.node(id).data[:id] }
        end

        private def pick(node, document, clause_ids, position)
          Export::SectionPick.new(
            collection: tree.collection_of(node.id).label,
            document_key: document.data[:document_key],
            title: document.data[:title],
            source_path: document.data[:source_path],
            section_id: node.data[:section_id],
            kind: node.data[:kind],
            label: node.data[:label],
            path: tree.section_path(node.id).map { |each| each.data[:label] },
            depth: node.depth - 2,
            order: [position, node.data[:ordinal].to_i],
            clause_ids:
          )
        end
      end
    end
  end
end
