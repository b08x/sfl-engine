# frozen_string_literal: true

module SFL
  module Core
    module Loaders
      class JsonRecordsSource
        # Reads the text of one chat message from its "text" field only.
        module MessageText
          # Returns the text of a message, or nil when the message is not a
          # Hash, has no "text" key, or has a null "text". A non-String value
          # yields the String values it holds, joined by one line break, so
          # the result is "" when it holds no String.
          # @return [String, nil]
          def self.extract(message)
            return nil unless message.is_a?(Hash) && message.key?("text")
            return nil if message["text"].nil?

            strings_joined(message["text"])
          end

          # Walks the value without recursion, so a deeply nested value cannot
          # overflow the stack. Blank Strings are dropped.
          private_class_method def self.strings_joined(value)
            found = []
            stack = [value]
            until stack.empty?
              node = stack.pop
              case node
              when String then found << node unless node.strip.empty?
              when Array then stack.concat(node.reverse)
              when Hash then stack.concat(node.values.reverse)
              end
            end
            found.one? ? found.first : found.join("\n")
          end
        end
      end
    end
  end
end
