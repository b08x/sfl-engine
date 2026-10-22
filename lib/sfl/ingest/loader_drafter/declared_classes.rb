# frozen_string_literal: true

module SFL
  module Ingest
    class LoaderDrafter
      # Gate G3's AST walker, extracted from LoaderDrafter: the full
      # constant path of every class a parsed candidate draft declares, so
      # both nested (`module SFL ... module Loaders ... class Foo`) and
      # compact (`class SFL::Core::Loaders::Foo`) styles resolve equally.
      # A CLASS node contributes its qualified name but does not widen the
      # namespace for its body; only MODULE does.
      class DeclaredClasses
        NODE = RubyVM::AbstractSyntaxTree::Node

        # @param node [RubyVM::AbstractSyntaxTree::Node] parsed root node
        # @return [Array<String>] full constant paths of every class the
        #   source declares, outermost first
        def self.of(node)
          new.walk(node)
        end

        def initialize(namespace = [])
          @namespace = namespace
        end

        # Non-node children (nil, literals) resolve to no declarations.
        def walk(node)
          return [] unless node.is_a?(NODE)

          case node.type
          when :MODULE then module_declarations(node)
          when :CLASS then class_declarations(node)
          else node.children.flat_map { |child| walk(child) }
          end
        end

        private def module_declarations(node)
          scope = namespaced(constant_path(node.children.first))
          node.children.drop(1).flat_map { |child| self.class.new(scope).walk(child) }
        end

        private def class_declarations(node)
          [namespaced(constant_path(node.children.first))]
            .concat(node.children.drop(1).flat_map { |child| walk(child) })
        end

        private def namespaced(name)
          @namespace.empty? ? name : "#{@namespace}::#{name}"
        end

        # Full constant path of a MODULE/CLASS name node. Nested single
        # names arrive as COLON2(nil, :Name) on this Ruby's AST and
        # collapse to the bare name; anything that is not a constant path
        # node resolves to "".
        private def constant_path(node)
          return "" unless node.is_a?(NODE)

          case node.type
          when :COLON2 then colon2(node)
          when :CONST, :COLON3 then scoped_name(node)
          else ""
          end
        end

        private def colon2(node)
          parent = constant_path(node.children.first)
          name = node.children.last.to_s
          parent.empty? ? name : "#{parent}::#{name}"
        end

        private def scoped_name(node)
          return "::#{node.children.last}" unless node.type == :CONST

          node.children.first.to_s
        end
      end
    end
  end
end
