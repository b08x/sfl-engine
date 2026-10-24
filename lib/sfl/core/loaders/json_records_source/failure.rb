# frozen_string_literal: true

module SFL
  module Core
    module Loaders
      class JsonRecordsSource
        # Raised when a file cannot be ingested as a whole. reason is one of
        # not_an_array, truncated or parse_error. byte_offset is an Integer.
        # partial holds the binary text of a record that was cut off at end of
        # input, or nil when no record was in progress.
        class Failure < Loaders::Error
          attr_reader :file, :reason, :byte_offset, :partial

          def initialize(file:, reason:, byte_offset:, partial: nil)
            @file = file
            @reason = reason
            @byte_offset = byte_offset
            @partial = partial
            super("#{file}: #{reason} at byte #{byte_offset}")
          end
        end
      end
    end
  end
end
