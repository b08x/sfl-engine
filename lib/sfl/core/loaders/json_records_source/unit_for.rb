# frozen_string_literal: true

module SFL
  module Core
    module Loaders
      class JsonRecordsSource
        # Builds the Types::Unit for one message of a document record.
        module UnitFor
          # @return [Types::Unit]
          def self.call(record:, number:, text:, message:, path:)
            uuid = record["uuid"]
            human = message["sender"] == "human"
            Types::Unit.new(
              section_id: "#{uuid}#turn-#{number}",
              text:,
              speaker: human ? "Human" : "Assistant",
              is_user: human,
              document_key: uuid,
              source_path: path,
              sent_at: sent_at(message["created_at"]),
              metadata: { "conversation_id" => uuid, "conversation_title" => record["name"] }
            )
          end

          # @return [Time, nil] nil when the value does not parse
          def self.sent_at(value)
            Time.parse(value.to_s)
          rescue ArgumentError
            nil
          end
        end
      end
    end
  end
end
