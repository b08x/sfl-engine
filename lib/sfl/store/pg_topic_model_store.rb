# frozen_string_literal: true

require "sequel"

module SFL
  module Store
    # Postgres store for fitted topic-model results over the `topic_models`
    # table (migration 022). Every fit is kept: #save always inserts, and
    # #latest reads the row with the highest id for a document.
    class PgTopicModelStore
      # @param db [Sequel::Database]
      def initialize(db)
        @db = db
      end

      # @param collection_key [String]
      # @param document_key [String]
      # @param result [Hash] with :topics (Array<Integer>), :topic_words
      #   (Hash<Integer, Array<String>>), :coverage (Float) and :attempts (Integer).
      # @param run_id [String, nil] SFL_RUN_ID of the producing run, or nil.
      # @return [Integer] the id of the new row.
      # @raise [Error] when a result key is missing or has the wrong type.
      def save(collection_key:, document_key:, result:, run_id: nil)
        validate!(result)
        row = {
          collection_key:,
          document_key:,
          topics: Sequel.pg_jsonb(result.fetch(:topics)),
          topic_words: Sequel.pg_jsonb(encode_topic_words(result.fetch(:topic_words))),
          coverage: result.fetch(:coverage),
          attempts: result.fetch(:attempts),
          run_id:,
        }
        guard("save") { @db[:topic_models].insert(row) }
      end

      # @return [Hash, nil] the newest fit for the document, or nil when none exists.
      def latest(collection_key:, document_key:)
        row = guard("latest") do
          @db[:topic_models].where(collection_key:, document_key:).order(Sequel.desc(:id)).first
        end
        return nil unless row

        {
          topics: row[:topics].to_a,
          topic_words: decode_topic_words(row[:topic_words]),
          coverage: row[:coverage],
          attempts: row[:attempts],
          run_id: row[:run_id],
          created_at: row[:created_at],
        }
      end

      # @return [Integer] the number of fits kept for the document.
      def count(collection_key:, document_key:)
        guard("count") { @db[:topic_models].where(collection_key:, document_key:).count }
      end

      private def validate!(result)
        raise Error, "topic model result must be a Hash, got #{result.class}" unless result.is_a?(Hash)

        require_type!(result, :topics, Array) { |v| v.all?(Integer) }
        require_type!(result, :topic_words, Hash) do |v|
          v.all? { |topic, words| topic.is_a?(Integer) && words.is_a?(Array) && words.all?(String) }
        end
        require_type!(result, :coverage, Float)
        require_type!(result, :attempts, Integer)
      end

      private def require_type!(result, key, klass)
        raise Error, "topic model result is missing #{key.inspect}" unless result.key?(key)

        value = result[key]
        ok = value.is_a?(klass) && (!block_given? || yield(value))
        raise Error, "topic model result #{key.inspect} has the wrong type (#{value.class})" unless ok
      end

      private def encode_topic_words(topic_words)
        topic_words.to_h { |topic, words| [topic.to_s, words] }
      end

      private def decode_topic_words(stored)
        stored.to_h.to_h { |topic, words| [Integer(topic, 10), words.to_a] }
      end

      private def guard(operation)
        yield
      rescue Sequel::DatabaseError => e
        raise Error, "topic model store #{operation} failed: #{e.message}"
      end
    end
  end
end
