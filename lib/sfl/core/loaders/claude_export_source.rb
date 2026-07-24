# frozen_string_literal: true

require "yajl"
require "time"

module SFL
  module Core
    module Loaders
      # Normalizes a Claude.ai web export (conversations.json, with
      # optional memories.json) into Types::Unit turns. Ported from
      # legacy ClaudeExportLoader (logic unchanged; parses via yajl-ruby
      # instead of stdlib JSON, and each turn is its own Unit — fixes D4).
      #
      # Shape recovered from ConvoWorkbench's client-side builder.ts
      # (deleted, pre-dates this Ruby port). Tool-use content blocks
      # (Claude's inline "artifacts") are intentionally not extracted
      # here — this loader's job is text-for-SFL-annotation, not
      # full-fidelity artifact capture.
      class ClaudeExportSource
        include Source

        def initialize(conversations_path, memories_path: nil)
          @conversations_path = conversations_path.to_s
          @memories_path = memories_path&.to_s
        end

        def each_unit
          return to_enum(:each_unit) unless block_given?

          conversations.each do |convo|
            turns = Array(convo[:chat_messages]).filter_map { |msg| turn_for(msg) }
            turns.each_with_index { |turn, index| yield build_unit(convo, turn, index) }
          end
        end

        # Memories don't carry role/turn structure — they're standing
        # facts, not dialogue. Returned separately rather than forced
        # into Types::Unit; how (or whether) to compile them is left to
        # the caller.
        # @return [Array<Hash>]
        def memories
          return [] unless @memories_path && File.exist?(@memories_path)

          Yajl::Parser.parse(File.read(@memories_path), symbolize_keys: true)
        end

        private def conversations
          Yajl::Parser.parse(File.read(@conversations_path), symbolize_keys: true)
        end

        private def build_unit(convo, turn, index)
          Types::Unit.new(
            document_id: "#{convo[:uuid]}#turn-#{index}",
            text: turn[:mes],
            speaker: turn[:name],
            is_user: turn[:is_user],
            sent_at: parse_sent_at(turn[:send_date]),
            metadata: { "conversation_id" => convo[:uuid], "conversation_title" => convo[:name] }
          )
        end

        private def parse_sent_at(send_date)
          send_date ? Time.parse(send_date.to_s) : nil
        rescue ArgumentError
          nil
        end

        private def turn_for(msg)
          text = message_text(msg)
          return nil if text.nil? || text.strip.empty?

          is_human = msg[:sender] == "human"
          {
            name: is_human ? "Human" : "Assistant",
            is_user: is_human,
            send_date: msg[:created_at],
            mes: text,
          }
        end

        # Claude messages carry both a flat `.text` and, when the model
        # used tools/artifacts, a richer `.content` block array — prefer
        # the text blocks from `.content` when present (matches
        # builder.ts's own precedence), since `.text` can be stale/empty
        # on tool-use turns.
        private def message_text(msg)
          blocks = Array(msg[:content])
          text_blocks = blocks.select { |b| b[:type] == "text" }.map { |b| b[:text] }
          return text_blocks.join("\n\n") unless text_blocks.empty?

          msg[:text]
        end
      end
    end
  end
end
