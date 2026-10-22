# frozen_string_literal: true

module SFL
  module TUI
    module Browse
      # Selected Browse rows, as an immutable set of Tree node ids.
      #
      # Selecting a node selects every known descendant. A node whose known
      # descendants are all selected becomes selected itself, provided all
      # of its descendants are known (Tree#complete?). Deselecting a node
      # also deselects its ancestors, because they are no longer whole.
      class Selection
        attr_reader :ids

        def initialize(ids = Set.new)
          @ids = ids.to_set.freeze
          freeze
        end

        # @return [Symbol] :full, :partial or :none
        def state(tree, id)
          return :full if @ids.include?(id)
          return :partial if tree.descendants(id).any? { |each| @ids.include?(each) }

          :none
        end

        def toggle(tree, id) = (state(tree, id) == :full) ? deselect(tree, id) : select(tree, id)

        def select(tree, id) = Selection.new(normalize(tree, @ids | [id, *tree.descendants(id)], id))

        def deselect(tree, id) = Selection.new(@ids - [id, *tree.descendants(id), *tree.ancestors(id)])

        # @param ids [Array<String>]
        def select_all(tree, ids) = ids.reduce(self) { |selection, id| selection.select(tree, id) }

        def clear = Selection.new

        def empty? = @ids.empty?

        # Adds the clauses of a selected section once they are loaded, so a
        # whole section stays whole.
        def absorb(tree, section_node_id)
          return self unless @ids.include?(section_node_id)

          Selection.new(@ids | tree.descendants(section_node_id))
        end

        # @return [Hash] `{sections:, clauses:}` counts; a selected section
        #   whose clauses are not loaded counts its stored clause_count
        def counts(tree)
          sections = tree.sections.select { |node| @ids.include?(node.id) }
          unloaded = sections.reject { |node| tree.loaded?(node.id) }.sum { |node| node.data[:clause_count].to_i }
          clauses = @ids.count { |id| tree.node(id)&.kind == :clause }
          { sections: sections.size, clauses: clauses + unloaded }
        end

        private def normalize(tree, ids, id)
          tree.ancestors(id).each do |ancestor|
            break unless tree.complete?(ancestor) && tree.children(ancestor).all? { |child| ids.include?(child) }

            ids |= [ancestor]
          end
          ids
        end
      end
    end
  end
end
