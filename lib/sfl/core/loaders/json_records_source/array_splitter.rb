# frozen_string_literal: true

module SFL
  module Core
    module Loaders
      class JsonRecordsSource
        # Streams the elements of a top-level JSON array from an IO. For each
        # element it yields the element's raw text, its byte offset and its
        # index. An element's contents are not interpreted here. Structural
        # faults raise Failure: a value outside the array, a missing or doubled
        # comma, a stray closing bracket, or input that ends early (truncated).
        #
        # Tokens come from TokenReader. An element is copied out of the buffer
        # once, so no per-token String is built.
        class ArraySplitter
          # Bytes of element text between collections. Each element is a String
          # the allocator holds until the next GC, so without this the peak
          # resident size grows with the file. A collection every COLLECT_EVERY
          # bytes keeps that peak near the size of a few elements.
          COLLECT_EVERY = 512 << 10
          OPEN_BYTES = [91, 123].freeze
          CLOSE_BYTES = [93, 125].freeze
          COMMA = 44
          CLOSER = { 91 => 93, 123 => 125 }.freeze

          # @param io [IO] opened in binary mode
          # @param file [String] the name used in errors
          def initialize(io, file:)
            @file = file
            @reader = TokenReader.new(io, file:)
            @state = :before
            @last = nil
            @index = 0
            @stack = []
            @collect_due = 0
          end

          # @yield [text, byte_offset, index] for each top-level element
          # @raise [Failure]
          def each_element(&block)
            return to_enum(:each_element) unless block

            @state = :before
            while (token = @reader.next_token)
              step(*token, &block)
            end
            @reader.fail_truncated! unless @state == :after
          end

          private def step(kind, start, length, &)
            case @state
            when :before then before_array!(kind, start)
            when :after then fail_at!(start) unless kind == :space
            when :array then in_array!(kind, start, length, &)
            when :element then in_element!(kind, start, length, &)
            end
          end

          private def before_array!(kind, start)
            return if kind == :space
            raise fault("not_an_array", 0) unless punct?(kind, start, 91)

            @state = :array
            @last = :open
          end

          private def in_array!(kind, start, length, &)
            return if kind == :space
            return close_array!(start) if punct?(kind, start, 93)
            return separator!(start) if punct?(kind, start, COMMA)

            start_value!(kind, start, length, &)
          end

          private def close_array!(start)
            fail_at!(start) if @last == :comma

            @state = :after
          end

          private def separator!(start)
            fail_at!(start) unless @last == :value

            @last = :comma
          end

          private def start_value!(kind, start, length, &)
            fail_at!(start) unless %i[open comma].include?(@last)
            fail_at!(start) if punct?(kind, start, 125)
            return begin_container(start) if kind == :punct

            emit(@reader.text(start, length), @reader.absolute(start), &)
          end

          private def begin_container(start)
            @state = :element
            @reader.open_element(start)
            @stack = [CLOSER.fetch(@reader.byte_at(start))]
          end

          private def in_element!(kind, start, length, &)
            return unless kind == :punct

            byte = @reader.byte_at(start)
            if OPEN_BYTES.include?(byte)
              @stack.push(CLOSER.fetch(byte))
            elsif CLOSE_BYTES.include?(byte)
              fail_at!(start) unless @stack.last == byte

              @stack.pop
              finish_container(start + length, &) if @stack.empty?
            end
          end

          private def finish_container(end_at, &)
            offset = @reader.element_offset
            text = @reader.element_text(end_at)
            @state = :array
            emit(text, offset, &)
          end

          private def emit(text, offset)
            index = @index
            @index += 1
            @last = :value
            collect_when_due(text.bytesize)
            yield text, offset, index
          end

          private def collect_when_due(bytes)
            @collect_due += bytes
            return if @collect_due < COLLECT_EVERY

            @collect_due = 0
            GC.start
          end

          private def punct?(kind, start, byte) = kind == :punct && @reader.byte_at(start) == byte

          private def fail_at!(position) = raise(fault("parse_error", @reader.absolute(position)))

          private def fault(reason, byte_offset)
            Failure.new(file: @file, reason:, byte_offset:)
          end
        end
      end
    end
  end
end
