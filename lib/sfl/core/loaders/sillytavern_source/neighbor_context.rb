# frozen_string_literal: true

module SFL
  module Core
    module Loaders
      class SillyTavernSource
        # Builds the warning context for one record of a parsed session: where
        # the record sits, and the speaker and flags of the records on each
        # side. Message text is never included. A neighbour that does not
        # exist gives nil.
        module NeighborContext
          # Cap on a neighbour name in characters, after sanitizing.
          MAX_NAME_CHARS = 64

          # @param records [Array<Hash>] every parsed record of the file, in order
          # @param index [Integer] position of the record being reported
          # @return [Hash{Symbol => String, Boolean, nil}] keyword fields for a log call
          def self.fields(records, index)
            previous = index.positive? ? records[index - 1] : nil
            following = records[index + 1]
            {
              position: position(index, following),
              previous_name: name(previous),
              next_name: name(following),
              previous_is_user: flag(previous, "is_user"),
              next_is_user: flag(following, "is_user"),
              previous_is_system: flag(previous, "is_system"),
              next_is_system: flag(following, "is_system"),
            }
          end

          def self.position(index, following)
            return "first" if index.zero?

            following ? "middle" : "last"
          end

          # Returns the record's name made safe for one log line, or nil when the
          # name is not a String or is empty after sanitizing. Control characters
          # become spaces, whitespace runs collapse, and the result is capped.
          def self.name(record)
            value = record["name"] if record
            return nil unless value.is_a?(String)

            clean = SingleLine.call(value)[0, MAX_NAME_CHARS].strip
            clean.empty? ? nil : clean
          end

          def self.flag(record, key) = record ? record[key] == true : nil

          private_class_method :position, :name, :flag
        end
      end
    end
  end
end
