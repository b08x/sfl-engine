# frozen_string_literal: true

require "stringio"

module SFL
  module Core
    module Ports
      module Fake
        # Scriptable CorpusSource for specs. Takes an array of simple
        # Struct refs (or FileRef-like doubles) and yields them in order.
        class CorpusSource
          include Ports::CorpusSource

          # @param refs [Array] objects responding to #read, #name,
          #   #extension, #content_identity, #size_bytes, #mtime, #source_id
          def initialize(refs)
            @refs = refs
          end

          attr_reader :refs

          def each_ref(&)
            return enum_for(:each_ref) unless block_given?

            @refs.each(&)
          end

          def stats
            {}
          end
        end

        # A minimal in-memory Ref for specs: holds text and returns it
        # from #read. No filesystem access.
        class Ref
          attr_reader :name, :extension, :content_identity, :size_bytes, :mtime, :source_id, :path_hint

          # @param text [String] the file content
          # @param name [String] basename without extension
          # @param extension [String] dot-prefixed extension
          # @param source_id [String] source identifier
          def initialize(text:, name:, extension:, source_id: "fake")
            @text = text
            @name = name
            @extension = extension
            @content_identity = "#{name}#{extension}:#{text.bytesize}"
            @size_bytes = text.bytesize
            @mtime = nil
            @source_id = source_id
            @path_hint = nil
          end

          def read(limit = nil)
            limit ? @text.byteslice(0, limit) : @text
          end
        end
      end
    end
  end
end
