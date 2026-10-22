# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Fake
        # In-memory BrowseSource built from nested Hashes, for specs.
        #
        #   Fake::BrowseSource.new(
        #     collections: [{ id: 1, name: "c", documents: [{ id: 10, document_key: "k", sections: [...] }] }],
        #     clauses: { "k#a" => [{ id: "x", text: "..." }] }
        #   )
        class BrowseSource
          include Ports::BrowseSource

          # @param collections [Array<Hash>] each with `documents:`, each with `sections:` (nested `children:`)
          # @param clauses [Hash{String => Array<Hash>}] by section id
          # @param content_reviews [Array<Hash>]
          # @param annotation_reviews [Hash{String => Hash}]
          def initialize(collections: [], clauses: {}, content_reviews: [], annotation_reviews: {})
            @collections = collections
            @clauses = clauses
            @content_reviews = content_reviews
            @annotation_reviews = annotation_reviews
          end

          def collections = @collections.map { |row| row.except(:documents) }

          def documents(collection_id)
            @collections.find { |row| row[:id] == collection_id }.fetch(:documents, []).map { |row| row.except(:sections) }
          end

          def sections(document_id) = all_documents.find { |row| row[:id] == document_id }.fetch(:sections, [])

          def clauses(section_id) = @clauses.fetch(section_id, []).map { |row| { section_id: }.merge(row) }

          attr_reader :content_reviews, :annotation_reviews

          # Replaces one content-review item's status, as a decision would.
          def update_review(id, status:)
            @content_reviews = @content_reviews.map { |row| (row[:id] == id) ? row.merge(status:) : row }
          end

          def locate(section_ids)
            index = {}
            @collections.each do |collection|
              collection.fetch(:documents, []).each do |document|
                walk(document.fetch(:sections, [])) do |section|
                  index[section[:section_id]] = {
                    collection: collection[:name],
                    document_key: document[:document_key],
                    source_path: document[:source_path],
                    label: section[:label],
                  }
                end
              end
            end
            index.slice(*section_ids)
          end

          private def all_documents = @collections.flat_map { |row| row.fetch(:documents, []) }

          private def walk(sections, &)
            sections.each do |section|
              yield(section)
              walk(section.fetch(:children, []), &)
            end
          end
        end
      end
    end
  end
end
