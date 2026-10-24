# frozen_string_literal: true

module SFL
  module Core
    module Loaders
      class SillyTavernSource
        # Makes an untrusted String safe to place in one log line or one error
        # message. Control characters become spaces, whitespace runs collapse
        # to one space, and the ends are stripped. No length cap is applied.
        module SingleLine
          # @param value [String] untrusted text, such as a neighbour name or a file basename
          # @return [String] the sanitized text, possibly empty
          def self.call(value)
            value.scrub.gsub(/[[:cntrl:]]/, " ").gsub(/\s+/, " ").strip
          end
        end
      end
    end
  end
end
