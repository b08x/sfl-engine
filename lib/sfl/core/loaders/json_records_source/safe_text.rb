# frozen_string_literal: true

module SFL
  module Core
    module Loaders
      class JsonRecordsSource
        # Makes a value safe for one log line: every control character,
        # including a carriage return or line feed, becomes one space.
        module SafeText
          KEY_LIMIT = 64

          # @return [String] the value as one line
          def self.line(value) = value.to_s.gsub(/[[:cntrl:]]/, " ")

          # @return [String] the value as one line, cut to KEY_LIMIT characters
          def self.key(value) = line(value)[0, KEY_LIMIT]
        end
      end
    end
  end
end
