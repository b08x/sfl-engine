# frozen_string_literal: true

module SFL
  module Analysis
    # Cleans turn texts on the topic-model input path only. Pure string
    # processing: no ENV, no I/O, no logger. Input strings are never mutated,
    # and the output has the same length and order as the input.
    #
    # Removes, in order:
    #   1. a leading "<Name>:" or "[<Name>]" label for each configured speaker
    #      name (case-insensitive, start of text only)
    #   2. whole lines that are system preambles ("You are..." under 200
    #      characters), tool-call traces, or repeated "#" header lines
    #
    # Then collapses every whitespace run to one space and strips both ends.
    class TopicInputCleaner
      PREAMBLE_PREFIX = "You are"
      PREAMBLE_MAX_LENGTH = 200
      TOOL_TRACE_PREFIXES = ["[tool", "Tool call:", "Tool result:"].freeze
      HEADER_PREFIX = "#"
      LINE_SEPARATOR = "\n"
      WHITESPACE_RUN = /\s+/

      def initialize(speaker_names: [])
        @speaker_label = build_speaker_label(speaker_names)
      end

      def call(texts)
        texts.map { |text| clean(text) }
      end

      private def clean(text)
        unlabelled = strip_speaker_label(text)
        kept = drop_boilerplate_lines(unlabelled.split(LINE_SEPARATOR, -1))
        kept.join(LINE_SEPARATOR).gsub(WHITESPACE_RUN, " ").strip
      end

      private def strip_speaker_label(text)
        return text if @speaker_label.nil?

        text.sub(@speaker_label, "")
      end

      # Returns nil when there are no names, so the label rule is skipped.
      private def build_speaker_label(names)
        escaped = Array(names).map { |name| name.to_s.strip }.reject(&:empty?).map { |name| Regexp.escape(name) }
        return nil if escaped.empty?

        alternatives = escaped.flat_map { |name| ["\\[#{name}\\]", "#{name}:"] }
        Regexp.new("\\A\\s*(?:#{alternatives.join('|')})\\s*", Regexp::IGNORECASE)
      end

      private def drop_boilerplate_lines(lines)
        seen_headers = {}
        lines.reject { |line| boilerplate_line?(line) || repeated_header?(line, seen_headers) }
      end

      private def boilerplate_line?(line)
        preamble_line?(line) || tool_trace_line?(line)
      end

      private def preamble_line?(line)
        line.start_with?(PREAMBLE_PREFIX) && line.length < PREAMBLE_MAX_LENGTH
      end

      private def tool_trace_line?(line)
        TOOL_TRACE_PREFIXES.any? { |prefix| line.start_with?(prefix) }
      end

      # The first occurrence of a header line is kept; later exact duplicates are dropped.
      private def repeated_header?(line, seen_headers)
        return false unless line.start_with?(HEADER_PREFIX)
        return true if seen_headers.key?(line)

        seen_headers[line] = true
        false
      end
    end
  end
end
