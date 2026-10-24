# frozen_string_literal: true

module SFL
  module Core
    module Loaders
      class JsonRecordsSource
        # Reads the conversation uuid from the start of a record cut off at
        # end of input. Returns nil unless the record opens with a plain
        # "uuid" String, with no escape in it, so a returned value is exact.
        module PartialKey
          PATTERN = /\A\s*\{\s*"uuid"\s*:\s*"([^"\\]*)"/

          # @param text [String] the binary text of the cut-off record
          # @return [String, nil]
          def self.call(text)
            match = PATTERN.match(text)
            match && match[1].force_encoding(Encoding::UTF_8)
          end
        end
      end
    end
  end
end
