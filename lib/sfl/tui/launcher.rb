# frozen_string_literal: true

require "shellwords"

module SFL
  module TUI
    # The ingest launcher: an overlay Program opens over any tab with `i`.
    # It takes a path, a collection (an existing one, picked with ↑/↓, or a
    # new name typed in) and the ingest flags, and starts
    # `sfl-analyze ingest --collection NAME [flags] PATH` through
    # Launcher::Commands. Pure: update returns the next state and, on
    # Enter, the request to start; it never does I/O.
    module Launcher
      ROOT = File.expand_path("../../..", __dir__)
      EXE = File.join(ROOT, "exe", "sfl-analyze")
      FIELDS = %i[path collection flags].freeze
      HELP = "Tab/Shift-Tab field · ↑/↓ existing collection · Enter start · Esc cancel"
      # Keys with a fixed action; any other single character is typed into
      # the focused field.
      KEY_ACTIONS = {
        "esc" => :cancel,
        "enter" => :submit,
        "tab" => :next_field,
        "back_tab" => :previous_field,
        "shift_back_tab" => :previous_field,
        "up" => :arrow_up,
        "down" => :arrow_down,
        "backspace" => :backspace,
      }.freeze

      # - `field`: index into FIELDS of the field keys type into
      # - `collections`: names of the existing collections
      # - `error`: why the last Enter was refused, nil for none
      State = Data.define(:path, :collection, :flags, :field, :collections, :error) do
        def focus = FIELDS.fetch(field)

        # @return [Boolean] whether the collection names an existing one
        def existing? = collections.any? { |name| name.casecmp?(collection.strip) }
      end

      # What Enter starts. `path` is absolute; `flags` is an argv fragment.
      Request = Data.define(:path, :collection, :flags) do
        # @return [Array<String>] the ingest command
        def argv = [EXE, "ingest", "--collection", collection, *flags, path]
      end

      extend self

      # @param collections [Array<String>]
      # @return [State]
      def open(collections) = State.new(path: "", collection: "", flags: "", field: 0, collections:, error: nil)

      # @return [Array(State|nil, Request|nil)] a nil state closes the launcher
      def update(state, key)
        action = KEY_ACTIONS[key]
        return __send__(action, state) if action

        [(key.length == 1) ? edit(state) { |text| text + key } : state, nil]
      end

      # @return [Request, String] the request, or why it is refused
      def request(state)
        path = state.path.strip
        return "path is required" if path.empty?

        flags = parse_flags(state.flags)
        return flags if flags.is_a?(String)

        absolute = File.expand_path(path)
        name = state.collection.strip
        Request.new(path: absolute, collection: name.empty? ? File.basename(absolute) : name, flags:)
      end

      private def submit(state)
        result = request(state)
        result.is_a?(Request) ? [nil, result] : [state.with(error: result), nil]
      end

      # Flags are checked with the CLI's own ingest option parser; the
      # collection has its own field and the path is not a flag.
      private def parse_flags(text)
        flags = Shellwords.split(text)
        rest = flags.dup
        options = CLI.parse_ingest_options(rest)
        return "set the collection in its own field" if options[:collection]
        return "not an ingest flag: #{rest.first}" unless rest.empty?

        flags
      rescue ArgumentError, OptionParser::ParseError => e
        "flags: #{e.message}"
      end

      private def cancel(_state) = [nil, nil]
      private def next_field(state) = [move(state, 1), nil]
      private def previous_field(state) = [move(state, -1), nil]
      private def arrow_up(state) = [arrow(state, -1), nil]
      private def arrow_down(state) = [arrow(state, 1), nil]
      private def backspace(state) = [edit(state) { |text| text[0...-1] }, nil]

      private def move(state, delta) = state.with(field: (state.field + delta) % FIELDS.size, error: nil)

      # In the collection field the arrows step through existing collections;
      # elsewhere they move between fields.
      private def arrow(state, delta)
        return move(state, delta) unless state.focus == :collection && state.collections.any?

        current = state.collections.index { |name| name.casecmp?(state.collection.strip) }
        index = current ? (current + delta) % state.collections.size : 0
        state.with(collection: state.collections.fetch(index), error: nil)
      end

      private def edit(state)
        field = state.focus
        state.with(field => yield(state.public_send(field)), :error => nil)
      end
    end
  end
end
