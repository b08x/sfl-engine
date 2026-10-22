# frozen_string_literal: true

require "sequel"

module SFL
  module Store
    # Postgres-backed collections. Names are trimmed and keep their case;
    # lookups ignore case (Core::CollectionName, migration 013).
    class PgCollectionRepository
      # @param db [Sequel::Database]
      def initialize(db)
        @db = db
      end

      # @param name [String]
      # @return [Hash] the existing row matching the name ignoring case, or a new row
      # @raise [Core::CollectionName::Error] for an empty name
      def find_or_create(name)
        name = Core::CollectionName.normalize(name)
        find(name) || insert(name)
      end

      # @param name [String]
      # @return [Hash, nil]
      def find(name)
        @db[:collections].where(Sequel.function(:lower, :name) => name.to_s.strip.downcase).first
      end

      # @return [Array<Hash>] every collection, by name
      def list = @db[:collections].order(Sequel.function(:lower, :name)).all

      private def insert(name)
        id = @db[:collections].insert(name:, created_at: Time.now)
        @db[:collections].where(id:).first
      rescue Sequel::UniqueConstraintViolation
        find(name)
      end
    end
  end
end
