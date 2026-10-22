# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Fake
        # In-memory SectionRegistry with the same move, replace and conflict
        # rules as Store::PgSectionRegistry, for specs without a database.
        # `documents` maps document_key to a Hash; `sections` maps section_id
        # to a Hash.
        class SectionRegistry
          include Ports::SectionRegistry

          attr_reader :documents, :sections

          # @param collection [String]
          # @param logger [Ports::Logger]
          # @param documents [Hash] pre-existing documents, keyed by document_key
          # @param sections [Hash] pre-existing sections, keyed by section_id
          def initialize(collection:, logger: Null::Logger.new, documents: {}, sections: {})
            @collection = CollectionName.normalize(collection)
            @logger = logger
            @documents = documents
            @sections = sections
            @claimed = {}
          end

          def transaction = yield

          def register(unit, clause_count)
            key = SectionShape.document_key(unit)
            refuse_move(unit.section_id, key)
            claim(unit, key) unless @claimed.key?(key)
            @claimed[key] += 1
            @sections[unit.section_id] = SectionShape.attributes(unit).merge(
              document_key: key, ordinal: @claimed[key], clause_count:,
              parent_section_id: @sections.key?(unit.parent_section_id) ? unit.parent_section_id : nil
            )
            @documents[key][:section_count] = @sections.count { |_, s| s[:document_key] == key }
            nil
          end

          private def refuse_move(section_id, key)
            owner = @sections.dig(section_id, :document_key)
            return if owner.nil? || owner == key

            @logger.warn("section owned by another document", section_id:, document_key: key, owner_document_key: owner)
            raise Ports::SectionRegistry::ConflictError, "section #{section_id} belongs to #{owner}, not #{key}"
          end

          private def claim(unit, key)
            existing = @documents[key]
            if existing && existing[:collection] != @collection
              @logger.warn("document moved", document_key: key, from_collection: existing[:collection],
                to_collection: @collection)
            end
            @sections.delete_if { |_, section| section[:document_key] == key }
            @documents[key] = SectionShape.document(unit).merge(collection: @collection, updated_at: Time.now)
            @claimed[key] = 0
          end
        end
      end
    end
  end
end
