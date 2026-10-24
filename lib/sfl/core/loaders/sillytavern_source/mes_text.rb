# frozen_string_literal: true

module SFL
  module Core
    module Loaders
      class SillyTavernSource
        # Reads the text of a non-String mes. Hash keys are not text; numbers
        # and booleans contribute nothing.
        module MesText
          # Returns the String leaves of value, depth-first in document order,
          # joined with a newline and stripped of surrounding whitespace.
          def self.extract(mes) = leaves(mes, []).join("\n").strip

          # Appends each String leaf of value to found, and returns found.
          def self.leaves(value, found)
            case value
            when String then found << value
            when Array then value.each { |item| leaves(item, found) }
            when Hash then value.each_value { |item| leaves(item, found) }
            end
            found
          end

          private_class_method :leaves
        end
      end
    end
  end
end
