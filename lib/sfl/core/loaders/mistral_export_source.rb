# frozen_string_literal: true

require "yajl"
require "time"

module SFL
  module Core
    module Loaders
      # Normalizes a Mistral Le Chat export into Types::Unit turns.
      # Ported from legacy MistralExportLoader (logic unchanged; parses
      # via yajl-ruby instead of stdlib JSON, and each turn is its own
      # Unit — fixes D4).
      #
      # Shape verified 2026-07-03 against a real export (Le Chat has no
      # documented/official export format — this loader is built
      # directly from a sample export file, not a spec, since none
      # exists): unlike Claude/ChatGPT, Le Chat exports one flat JSON
      # array per conversation (chat-<uuid>.json — no bundling file, no
      # tree structure, no separate title field).
      #
      # @param path [String] a single chat-<uuid>.json file, or a
      #   directory containing many of them (the export's actual
      #   on-disk shape)
      class MistralExportSource
        include Source

        def initialize(path)
          @path = path.to_s
        end

        def each_unit
          return to_enum(:each_unit) unless block_given?

          chat_files.each do |file|
            chat_id, turns = conversation_for(file)
            next if turns.empty?

            turns.each_with_index { |turn, index| yield build_unit(chat_id, turn, index) }
          end
        end

        private def chat_files
          File.directory?(@path) ? Dir.glob(File.join(@path, "chat-*.json")) : [@path]
        end

        private def conversation_for(file)
          messages = Yajl::Parser.parse(File.read(file), symbolize_keys: true)
          return [nil, []] if messages.empty?

          chat_id = messages.first[:chatId] || File.basename(file, ".json").delete_prefix("chat-")
          [chat_id, messages.filter_map { |msg| turn_for(msg) }]
        end

        private def build_unit(chat_id, turn, index)
          Types::Unit.new(
            document_id: "#{chat_id}#turn-#{index}",
            text: turn[:mes],
            speaker: turn[:name],
            is_user: turn[:is_user],
            sent_at: parse_sent_at(turn[:send_date]),
            metadata: { "conversation_id" => chat_id }
          )
        end

        private def parse_sent_at(send_date)
          send_date ? Time.parse(send_date.to_s) : nil
        rescue ArgumentError
          nil
        end

        private def turn_for(msg)
          text = msg[:content]
          return nil if text.nil? || text.strip.empty?

          is_user = msg[:role] == "user"
          {
            name: is_user ? "User" : "Mistral",
            is_user:,
            send_date: msg[:createdAt],
            mes: text,
          }
        end
      end
    end
  end
end
