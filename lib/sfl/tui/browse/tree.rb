# frozen_string_literal: true

module SFL
  module TUI
    module Browse
      # Immutable index of the Browse hierarchy: collections, documents,
      # nested sections and, once loaded, a section's clauses.
      #
      # Node ids are prefixed by kind: `c:<collection id>`, `d:<document id>`,
      # `s:<section_id>`, `k:<clause id>`.
      class Tree
        Node = Data.define(:id, :kind, :label, :depth, :parent_id, :child_ids, :data)

        attr_reader :roots

        # @param source [Core::Ports::BrowseSource]
        # @return [Tree] collections, documents and sections; no clauses
        def self.load(source)
          builder = Builder.new
          source.collections.each do |collection|
            builder.add_collection(collection, source.documents(collection[:id]).map do |document|
              [document, source.sections(document[:id])]
            end)
          end
          builder.tree
        end

        # @param nodes [Hash{String => Node}] in display order
        # @param roots [Array<String>]
        # @param loaded [Hash{String => true}] section node ids whose clauses are loaded
        def initialize(nodes: {}, roots: [], loaded: {})
          @nodes = nodes.freeze
          @roots = roots.freeze
          @loaded = loaded.freeze
          freeze
        end

        # @return [Node, nil]
        def node(id) = @nodes[id]

        # @return [Array<String>] child ids, clauses after child sections
        def children(id) = @nodes.fetch(id).child_ids

        # @return [Array<String>] parent first, root last
        def ancestors(id)
          chain = []
          current = @nodes[id]&.parent_id
          while current
            chain << current
            current = @nodes.fetch(current).parent_id
          end
          chain
        end

        # @return [Array<String>] every known descendant, depth first
        def descendants(id) = children(id).flat_map { |child| [child, *descendants(child)] }

        # @return [Array<Node>] section nodes in display order
        def sections = @nodes.values.select { |node| node.kind == :section }

        # @return [Boolean] whether the section's clauses are loaded
        def loaded?(id) = @loaded.key?(id)

        # Whether every descendant of the node is known: always for
        # collections and documents, and for a section once its clauses are
        # loaded or when it has none.
        def complete?(id)
          node = @nodes.fetch(id)
          return true unless node.kind == :section

          loaded?(id) || node.data[:clause_count].to_i.zero?
        end

        # @return [Array<Node>] the clause nodes of a loaded section
        def clauses(section_node_id) = children(section_node_id).filter_map { |id| clause_node(id) }

        # @return [Node, nil] the enclosing document node
        def document_of(id) = (ancestors(id).reverse + [id]).map { |each| @nodes[each] }.find { |node| node&.kind == :document }

        # @return [Node, nil] the enclosing collection node
        def collection_of(id) = (ancestors(id).reverse + [id]).map { |each| @nodes[each] }.find { |node| node&.kind == :collection }

        # @return [Array<Node>] the section and its enclosing sections, outermost first
        def section_path(id) = (ancestors(id).reverse + [id]).map { |each| @nodes[each] }.select { |node| node.kind == :section }

        # @param section_id [String]
        # @param clauses [Array<Hash>] rows from BrowseSource#clauses
        # @return [Tree] a copy with the section's clauses attached
        def with_clauses(section_id, clauses)
          sid = Browse.section_node(section_id)
          section = @nodes.fetch(sid)
          nodes = without_clauses_of(sid)
          clause_ids = attach_clauses(nodes, section, clauses)
          nodes[sid] = section.with(child_ids: child_sections(section) + clause_ids)
          self.class.new(nodes:, roots: @roots, loaded: @loaded.merge(sid => true))
        end

        private def without_clauses_of(sid) = @nodes.reject { |_id, node| node.kind == :clause && node.parent_id == sid }

        private def child_sections(section) = section.child_ids.reject { |id| @nodes[id]&.kind == :clause }

        # Adds a clause node under +section+ for each row; returns their ids in row order.
        private def attach_clauses(nodes, section, clauses)
          clauses.map do |clause|
            id = Browse.clause_node(clause[:id])
            nodes[id] = Node.new(id:, kind: :clause, label: clause[:text].to_s, depth: section.depth + 1,
              parent_id: section.id, child_ids: [], data: clause)
            id
          end
        end

        private def clause_node(id)
          node = @nodes[id]
          node if node&.kind == :clause
        end

        # Accumulates nodes in display order while Tree.load walks the source.
        class Builder
          def initialize
            @nodes = {}
            @roots = []
          end

          def add_collection(collection, documents)
            id = "c:#{collection[:id]}"
            @roots << id
            child_ids = documents.map { |document, sections| add_document(document, sections, id) }
            @nodes[id] = Node.new(id:, kind: :collection, label: collection[:name].to_s, depth: 0, parent_id: nil, child_ids:,
              data: collection)
          end

          def tree = Tree.new(nodes: order, roots: @roots)

          private def add_document(document, sections, parent_id)
            id = "d:#{document[:id]}"
            child_ids = sections.map { |section| add_section(section, id, 2) }
            label = document[:title] || document[:document_key]
            @nodes[id] = Node.new(id:, kind: :document, label: label.to_s, depth: 1, parent_id:, child_ids:,
              data: document)
            id
          end

          private def add_section(section, parent_id, depth)
            id = Browse.section_node(section[:section_id])
            child_ids = section.fetch(:children, []).map { |child| add_section(child, id, depth + 1) }
            @nodes[id] = Node.new(id:, kind: :section, label: (section[:label] || section[:section_id]).to_s, depth:,
              parent_id:, child_ids:, data: section.except(:children))
            id
          end

          # Depth-first display order: each node before its children.
          private def order
            ordered = {}
            visit = lambda do |id|
              ordered[id] = @nodes.fetch(id)
              @nodes.fetch(id).child_ids.each { |child| visit.call(child) }
            end
            @roots.each { |id| visit.call(id) }
            ordered
          end
        end
      end
    end
  end
end
