# frozen_string_literal: true

require "json_canvas"

module SFL
  module Core
    module Loaders
      # Obsidian .canvas files (JSON node-graph: nodes have a type of
      # group/file/text/link, positioned on an x/y/width/height plane,
      # connected by edges). Parsed via the json_canvas gem rather than
      # hand-rolled JSON traversal (legacy CanvasLoader did its own
      # `JSON.parse` + `node[:type] == "text"` filtering) — json_canvas
      # models each node type as its own class (TextNode/FileNode/
      # LinkNode/GroupNode), so "only TextNode carries prose" is a type
      # check (`is_a?(JsonCanvas::TextNode)`) rather than a string
      # comparison against a raw Hash key.
      #
      # Only TextNode carries prose worth SFL annotation. GroupNode is
      # pure layout (a label, no body). FileNode references another vault
      # file by path — deliberately not resolved/inlined here: that file
      # is its own document and gets its own artifact on a separate pass
      # over the vault; inlining it here would duplicate its clauses
      # under two document_ids. LinkNode (bare URLs) carries no local
      # prose either.
      class CanvasSource
        include Source

        # @param path [String, Pathname]
        # @param file_id [String, nil] Override the auto-derived file identifier.
        # @param skip_empty [Boolean] Drop text nodes whose content is blank/too short.
        # @param min_length [Integer] Minimum character length to emit a unit.
        def initialize(path, file_id: nil, skip_empty: true, min_length: 40)
          @path = path.to_s
          @file_id = file_id || File.basename(@path, ".*")
          @skip_empty = skip_empty
          @min_length = min_length
        end

        def each_unit
          return to_enum(:each_unit) unless block_given?

          text_nodes.each_with_index do |node, index|
            text = node.text.to_s.strip
            next unless emit?(text)

            yield build_unit(text, node.id || "node#{index + 1}")
          end
        end

        private def text_nodes
          canvas = JsonCanvas.parse(File.read(@path, encoding: "utf-8"))
          canvas.nodes.grep(::JsonCanvas::TextNode)
        end

        private def emit?(text) = !@skip_empty || text.length >= @min_length

        private def build_unit(text, slug)
          Types::Unit.new(
            document_id: "#{@file_id}##{slug}",
            text:,
            heading: "canvas node #{slug}",
            metadata: { "file_id" => @file_id, "heading_level" => 1, "heading_slug" => slug }
          )
        end
      end
    end
  end
end
