# frozen_string_literal: true

require "strscan"

module SFL
  module Core
    module Loaders
      class JsonRecordsSource
        class ArraySplitter
          # Reads an IO in chunks into one buffer and returns tokens by position.
          # A token is [kind, start, length], where start indexes the buffer. A
          # token that reaches the end of the buffer is read again once more
          # input is available, so no token is split across a read.
          #
          # Bytes before the open element, or before the scanner when no element
          # is open, are dropped in place, so the buffer holds about one chunk.
          class TokenReader
            CHUNK = 1 << 20
            STRING = /"[^"\\]*(?:\\.[^"\\]*)*"/m
            RUN = /\s+|[^\s,"\[\]{}]+/
            PUNCT = /[,\[\]{}]/
            QUOTE = 34
            PUNCT_BYTES = [44, 91, 93, 123, 125].freeze
            SPACE_BYTES = [9, 10, 11, 12, 13, 32].freeze

            # @param io [IO] opened in binary mode
            # @param file [String] the name used in errors
            def initialize(io, file:)
              @io = io
              @file = file
              @buffer = String.new(encoding: Encoding::BINARY)
              @chunk = String.new(capacity: CHUNK, encoding: Encoding::BINARY)
              @scanner = StringScanner.new(@buffer)
              @base = 0
              @eof = false
              @element_at = nil
            end

            # @return [Array(Symbol, Integer, Integer), nil] nil at the end of input
            # @raise [Failure] when input ends inside a token
            def next_token
              loop do
                if @scanner.eos?
                  return nil if @eof

                  fill
                  next
                end
                token = scan_token
                return token if token

                fail_truncated! if @eof
                fill
              end
            end

            def byte_at(position) = @buffer.getbyte(position)

            # @return [String] the UTF-8 text of buffer bytes from start for length bytes
            def text(start, length) = @buffer.byteslice(start, length).force_encoding(Encoding::UTF_8)

            # @return [Integer] the absolute byte offset of a buffer position
            def absolute(position) = @base + position

            # Marks where an element begins. Its bytes are kept until #element_text.
            def open_element(position)
              @element_at = position
            end

            # @return [Integer] the absolute offset of the open element
            def element_offset = @base + @element_at

            # @return [String] the open element's text, up to end_at, and closes it
            def element_text(end_at)
              text(@element_at, end_at - @element_at).tap { @element_at = nil }
            end

            # @raise [Failure] truncated at the end of the buffer, with any open element as partial
            def fail_truncated!
              partial = @element_at && @buffer.byteslice(@element_at, @buffer.bytesize - @element_at)
              raise Failure.new(file: @file, reason: "truncated", byte_offset: @base + @buffer.bytesize, partial:)
            end

            # Returns the next token, or nil when it may be incomplete. The scanner
            # is rewound to the token start in that case.
            private def scan_token
              start = @scanner.pos
              byte = byte_at(start)
              length = if byte == QUOTE then @scanner.skip(STRING)
              elsif PUNCT_BYTES.include?(byte) then @scanner.skip(PUNCT)
              else @scanner.skip(RUN)
              end
              if length.nil? || (@scanner.eos? && !@eof)
                @scanner.pos = start
                return nil
              end

              [kind_for(byte), start, length]
            end

            private def kind_for(byte)
              return :string if byte == QUOTE
              return :punct if PUNCT_BYTES.include?(byte)

              SPACE_BYTES.include?(byte) ? :space : :literal
            end

            private def fill
              compact
              if @io.read(CHUNK, @chunk)
                @buffer << @chunk
              else
                @eof = true
              end
            end

            private def compact
              keep = @element_at || @scanner.pos
              return if keep < CHUNK

              @base += keep
              @buffer.bytesplice(0, keep, "".b)
              @scanner.pos -= keep
              @element_at -= keep if @element_at
            end
          end
        end
      end
    end
  end
end
