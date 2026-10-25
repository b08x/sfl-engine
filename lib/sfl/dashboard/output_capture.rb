# frozen_string_literal: true

module SFL
  module Dashboard
    # Stands in for $stdout and $stderr while the dashboard is drawn, so a
    # stray `puts` or `warn` becomes a log line instead of text written over
    # the screen. Partial writes are buffered until a newline.
    class OutputCapture
      # @param board [Board]
      def initialize(board)
        @board = board
        @buffer = +""
      end

      # @return [Integer] bytes accepted
      def write(*parts)
        text = parts.join
        @buffer << text
        flush_lines
        text.bytesize
      end

      def <<(text)
        write(text)
        self
      end

      def print(*parts) = write(*parts) && nil

      def puts(*lines)
        lines = [""] if lines.empty?
        lines.flatten.each { |line| write(line.to_s.end_with?("\n") ? line.to_s : "#{line}\n") }
        nil
      end

      def printf(format, *) = write(Kernel.format(format, *)) && nil
      def flush = self
      def sync = true # rubocop:disable Naming/PredicateMethod -- IO#sync is the name callers use
      def sync=(_value); end
      def tty? = false
      alias isatty tty?
      def fileno = nil

      # Logger::LogDevice treats an object as an IO only when it answers both
      # write and close; without close it calls File.open on it. Closing does
      # nothing: the capture lives as long as the dashboard that owns it.
      def close = nil

      private def flush_lines
        while (index = @buffer.index("\n"))
          line = @buffer.slice!(0..index).chomp
          append(line) unless line.strip.empty?
        end
      end

      # A trap handler cannot take the Board's lock; its line is dropped.
      private def append(line)
        @board.update { |state| state.add_log(line) }
      rescue ThreadError
        nil
      end
    end
  end
end
