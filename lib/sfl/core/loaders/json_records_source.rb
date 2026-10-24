# frozen_string_literal: true

require "yajl"
require "time"

module SFL
  module Core
    module Loaders
      # Streams a top-level JSON array of records and yields one Types::Unit per
      # message. A Claude.ai conversations.json is one instance of this shape.
      #
      # A document record is an object with a String "uuid" and an Array
      # "chat_messages". Its document_key is the uuid; section_id is
      # "<uuid>#turn-N", with N counting the yielded messages from 0. A message
      # with no text is skipped with a warning, listed in #skipped under its
      # record_index, and does not use a number.
      # Text comes from each message's "text" field only.
      #
      # The reader holds one record at a time, so no size cap applies.
      # Warnings go through the logger with keyword fields; no message text
      # and no conversation name is logged. A uuid that is invalid or repeated
      # is skipped and listed in #skipped.
      class JsonRecordsSource
        include Source

        COMPONENT = "JsonRecordsSource"

        # Valid conversation uuids of the document records seen, in file order.
        # @return [Array<String>]
        attr_reader :document_keys

        # Records skipped for a uuid problem: { record_index:, reason: }.
        # @return [Array<Hash>]
        attr_reader :skipped

        # @param ref [SFL::Core::Refs::FileRef] the file to read
        # @param logger [Core::Ports::Logger]
        def initialize(ref, logger: Core::Ports::Null::Logger.new)
          @ref = ref
          @logger = logger
          @document_keys = []
          @skipped = []
          @keys = {}
        end

        # @yield [Types::Unit] one unit per yielded message, in file order
        # @return [Enumerator] when no block is given
        # @raise [Failure] when the file is not an array or is malformed or truncated
        def each_unit(&block)
          return to_enum(:each_unit) unless block

          @pending = []
          @records = false
          @documents = false
          File.open(@ref.path_hint, "rb") do |io|
            ArraySplitter.new(io, file: file_name).each_element do |text, offset, index|
              record(text, offset, index, &block)
            end
          end
          no_known_shape if @records && !@documents
        end

        private def record(text, offset, index, &)
          @records = true
          value = parse(text, offset)
          fault = shape_fault(value)
          if fault
            @pending << [fault, index]
          else
            @documents = true
            flush_pending
            document(value, index, &)
          end
        end

        private def shape_fault(value)
          return "not_a_record" unless value.is_a?(Hash)
          return "no_document_key" unless value["uuid"].is_a?(String)
          return "no_section_list" unless value["chat_messages"].is_a?(Array)

          nil
        end

        # Shape warnings wait until a document record shows the file has one,
        # so a file with no document record logs one warning and nothing else.
        private def flush_pending
          @pending.each { |reason, index| warn_record(reason, index) }
          @pending.clear
        end

        private def no_known_shape
          @logger.warn("json array holds no document records", component: COMPONENT, file: file_name, reason: "no_known_shape")
        end

        private def parse(text, offset)
          Yajl::Parser.parse(text)
        rescue Yajl::ParseError
          raise Failure.new(file: file_name, reason: "parse_error", byte_offset: offset)
        end

        private def document(record, index, &)
          uuid = record["uuid"]
          fault = key_fault(uuid)
          return skip(fault, index, uuid) if fault
          return skip("duplicate_document_key", index, uuid) if @keys.key?(uuid)

          @keys[uuid] = true
          @document_keys << uuid
          units(record, index, &)
        end

        private def key_fault(uuid) = (uuid.empty? || uuid.match?(/[#\r\n]/)) ? "invalid_document_key" : nil

        private def skip(reason, index, uuid)
          @skipped << { record_index: index, reason: }
          warn_record(reason, index, document_key: SafeText.key(uuid))
        end

        private def units(record, index, &)
          number = 0
          record["chat_messages"].each_with_index do |message, message_index|
            text = MessageText.extract(message)
            fault = text.nil? ? "text_missing" : nil
            fault ||= "text_empty" if text && text.strip.empty?
            if fault
              warn_message(fault, index, message_index)
              @skipped << { record_index: index, reason: fault }
              next
            end

            yield(unit(record, number, text, message))
            number += 1
          end
        end

        private def unit(record, number, text, message)
          UnitFor.call(record:, number:, text:, message:, path: @ref.path_hint)
        end

        private def warn_record(reason, index, **fields)
          @logger.warn("json record skipped", component: COMPONENT, file: file_name, record_index: index, reason:, **fields)
        end

        private def warn_message(reason, index, message_index)
          @logger.warn("json message skipped", component: COMPONENT, file: file_name, record_index: index, message_index:, reason:)
        end

        private def file_name = SafeText.line(File.basename(@ref.path_hint.to_s))
      end
    end
  end
end
