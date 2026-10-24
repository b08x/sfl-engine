# frozen_string_literal: true

require "json"

module SFL
  module Core
    module Loaders
      # Normalizes a SillyTavern group-chat session (one .jsonl file per chat
      # session) into Types::Unit turns. One file is one document. Each record
      # that yields text is one section (one turn). A system record with a
      # String mes is skipped without a warning. A system record with a
      # non-String mes is read like any other record and yields its text when
      # it has any.
      #
      # Each physical line is one complete JSON record. Line breaks inside a
      # message are stored as the two characters \n, so a record never spans
      # lines and the decoded text keeps any line break.
      #
      # mes is read as follows. A String mes is the text. A non-String mes
      # (array, object, number, boolean) yields the String values inside it,
      # joined with a newline. A missing or null mes skips the record with a
      # warning. Each skip or empty-text warning carries the position and the
      # speaker and flags of the neighbouring records.
      #
      # send_date strings carry no zone and are US Eastern wall-clock time.
      # sent_at is converted to a UTC Time with the offset in force on that
      # date (see SillyTavernSource::SendDate). A missing or unusable
      # send_date keeps the unit with sent_at nil and logs one warning through
      # Ports::Logger.
      #
      # The whole file is parsed before the first unit is yielded, so a fatal
      # error yields zero units from that file. Fatal cases raise
      # SillyTavernSource::SourceError (a Loaders::Error) for the ingest
      # boundary to rescue.
      class SillyTavernSource
        include Source

        # Raised for every fatal case. file is the basename of the session
        # file; line is the physical line where the failure is, or nil.
        class SourceError < Loaders::Error
          attr_reader :file, :line

          def initialize(message, file:, line: nil)
            super(message)
            @file = file
            @line = line
          end
        end

        # @param ref [SFL::Core::Refs::FileRef] a .jsonl ref
        # @param file_id [String] section id prefix and metadata file_id
        # @param logger [Core::Ports::Logger] receives the send_date and mes warnings
        def initialize(ref, file_id:, logger: Core::Ports::Null::Logger.new)
          @ref = ref
          @file_id = file_id
          @logger = logger
        end

        # @yield [Types::Unit] one unit per yielded record, in file order
        # @return [Enumerator] when no block is given
        def each_unit(&)
          return to_enum(:each_unit) unless block_given?

          session_turns.each_with_index.map { |(record, line, text), index| build_unit(record, line, text, index) }.each(&)
        end

        # Returns [record, line, text] for every record that yields a unit,
        # after the format, encoding and non-empty checks.
        private def session_turns
          raise failure("Unsupported session format: expected a .jsonl ref") unless jsonl?

          pairs = parse_records(content_lines)
          records = pairs.map(&:first)
          turns = pairs.each_with_index.filter_map do |(record, line), index|
            text = turn_text(record, line, records, index)
            [record, line, text] if text
          end
          raise failure("No session turns") if turns.empty?

          turns
        end

        # Returns the session text split into physical lines, after the UTF-8 check.
        private def content_lines
          content = @ref.read
          raise failure("Session is not valid UTF-8") unless content.valid_encoding?

          content.each_line.map(&:chomp)
        end

        # Returns [record, physical line number] pairs for every non-blank line.
        private def parse_records(lines)
          lines.each_with_index.filter_map do |text, index|
            next if text.strip.empty?

            line = index + 1
            [object!(parse_line(text, line), line), line]
          end
        end

        # Parses one physical line as one JSON record.
        private def parse_line(text, line)
          JSON.parse(text)
        rescue JSON::ParserError
          raise failure("Line #{line} is not valid JSON", line:)
        end

        # A record must be a JSON object. Any other shape is fatal.
        private def object!(record, line)
          return record if record.is_a?(Hash)

          raise failure("Record at line #{line} is not a message", line:)
        end

        # Returns the text the record yields, or nil when the record is skipped.
        # records and index give the neighbours for a warning.
        private def turn_text(record, line, records, index)
          mes = record["mes"]
          return warn_skipped("mes_missing", "mes missing, record skipped", line, records, index) if mes.nil?
          return string_turn_text(record, mes, line) if mes.is_a?(String)

          text = MesText.extract(mes)
          return warn_skipped("mes_no_text", "mes has no text, record skipped", line, records, index) if text.empty?

          text
        end

        # A String mes on a system record is skipped silently. Any other String mes is yielded whole.
        private def string_turn_text(record, mes, _line)
          return nil if record["is_system"] == true

          mes
        end

        # Logs one warning for a skipped record with its neighbour context. Returns nil.
        private def warn_skipped(reason, message, line, records, index)
          @logger.warn(message, component: "SillyTavernSource", file: file_name, line:, reason:, **NeighborContext.fields(records, index))
          nil
        end

        private def build_unit(record, line, text, index)
          Types::Unit.new(
            section_id: "#{@file_id}#turn-#{index}",
            text:,
            speaker: record["name"].to_s,
            is_user: record["is_user"] == true,
            document_key: @ref.path_hint,
            source_path: @ref.path_hint,
            sent_at: sent_at_for(record, line),
            metadata: { "file_id" => @file_id, "source_file" => file_name }
          )
        end

        # Returns the parsed UTC time, or nil after one warning when send_date
        # is absent or does not parse. SendDate.parse(nil) returns nil.
        private def sent_at_for(record, line)
          raw = record["send_date"]
          SendDate.parse(raw) || unusable_send_date(raw, line)
        end

        private def unusable_send_date(raw, line)
          @logger.warn("send_date unusable, sent_at left nil", component: "SillyTavernSource", file: file_name, line:, reason: raw.nil? ? "send_date_missing" : "send_date_unparseable")
          nil
        end

        # Every fatal message names the file, so the basename is never omitted.
        private def failure(message, line: nil) = SourceError.new("#{file_name}: #{message}", file: file_name, line:)

        private def jsonl? = @ref.extension.casecmp?(".jsonl")

        # The basename with control characters made spaces, so it stays on one log line.
        private def file_name = SingleLine.call(File.basename(@ref.path_hint.to_s))
      end
    end
  end
end
