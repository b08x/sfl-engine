# frozen_string_literal: true

require "yajl"
require "time"

module SFL
  module Core
    module Loaders
      # Normalizes a ChatGPT export (conversations.json) into Types::Unit
      # turns. Ported from legacy ChatGPTExportLoader (logic unchanged;
      # parses via yajl-ruby instead of stdlib JSON, and each turn is its
      # own Unit rather than a Hash nested inside a loader-local
      # Conversation struct — fixes D4).
      #
      # ChatGPT's export stores each conversation as a tree (`mapping`:
      # node id => {message, parent, children}) to support branching/
      # regen, not a flat list — the active thread is the path from
      # whichever leaf has no children back to the root, reversed into
      # chronological order. A conversation with multiple leaves (the
      # user regenerated a reply, or edited an earlier message) has more
      # than one possible thread; this loader takes the first leaf found,
      # matching legacy behavior — picking "the" canonical thread among
      # several isn't a decision a generic loader should make silently
      # beyond matching prior behavior.
      class ChatgptExportSource
        include Source

        def initialize(conversations_path)
          @conversations_path = conversations_path.to_s
        end

        def each_unit
          return to_enum(:each_unit) unless block_given?

          conversations.each do |convo|
            turns = linear_thread(convo[:mapping]).filter_map { |node| turn_for(node) }
            turns.each_with_index { |turn, index| yield build_unit(convo, turn, index) }
          end
        end

        private def conversations
          Yajl::Parser.parse(File.read(@conversations_path), symbolize_keys: true)
        end

        private def build_unit(convo, turn, index)
          Types::Unit.new(
            document_id: "#{convo[:id]}#turn-#{index}",
            text: turn[:mes],
            speaker: turn[:name],
            is_user: turn[:is_user],
            sent_at: turn[:send_date] ? Time.parse(turn[:send_date]) : nil,
            metadata: { "conversation_id" => convo[:id], "conversation_title" => convo[:title] }
          )
        end

        # Walks parent pointers from a leaf node back to the root, then
        # reverses into chronological order. Returns raw mapping nodes
        # (Hash), not turns — #turn_for does the role/text extraction.
        private def linear_thread(mapping)
          return [] unless mapping

          leaf = mapping.values.find { |n| Array(n[:children]).empty? }
          return [] unless leaf

          thread = []
          current = leaf
          while current
            thread << current if real_message?(current)
            current = parent_of(current, mapping)
          end
          thread.reverse
        end

        private def real_message?(node) = node[:message] && node.dig(:message, :author, :role) != "system"

        private def parent_of(node, mapping) = node[:parent] ? mapping[node[:parent].to_sym] : nil

        private def turn_for(node)
          message = node[:message]
          parts = Array(message.dig(:content, :parts)).join("\n")
          return nil if parts.strip.empty?

          is_user = message.dig(:author, :role) == "user"
          { name: is_user ? "User" : "ChatGPT", is_user:, mes: parts, send_date: send_date_for(message) }
        end

        private def send_date_for(message)
          create_time = message[:create_time]
          create_time ? Time.at(create_time).iso8601 : nil
        end
      end
    end
  end
end
