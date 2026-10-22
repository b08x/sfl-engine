# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Read side of the stored corpus for the TUI Browse and Search tabs:
      # collections, documents, nested sections, clauses and their review
      # state. Every method returns plain Hashes.
      module BrowseSource
        # @return [Array<Hash>] `{id:, name:}`, by name
        def collections
          raise NotImplementedError, "#{self.class} must implement #collections"
        end

        # @param collection_id [Integer]
        # @return [Array<Hash>] `{id:, document_key:, title:, source_path:}`, by document_key
        def documents(collection_id)
          raise NotImplementedError, "#{self.class} must implement #documents"
        end

        # @param document_id [Integer]
        # @return [Array<Hash>] top-level sections in ordinal order, each
        #   `{section_id:, label:, kind:, level:, ordinal:, clause_count:, children: [...]}`
        def sections(document_id)
          raise NotImplementedError, "#{self.class} must implement #sections"
        end

        # @param section_id [String]
        # @return [Array<Hash>] `{id:, text:, section_id:, ideational: Hash, interpersonal: Hash}`
        def clauses(section_id)
          raise NotImplementedError, "#{self.class} must implement #clauses"
        end

        # Content-review items (review_queue rows), every status.
        # @return [Array<Hash>] `{id:, section_id:, modality:, source_file:, generated_text:, reason:, status:}`
        def content_reviews
          raise NotImplementedError, "#{self.class} must implement #content_reviews"
        end

        # Annotation-review state per clause: "pending" for a clause in the
        # annotation review queue, otherwise the latest recorded decision.
        # @return [Hash{String => Hash}] clause id => `{status:, confidence:}`
        def annotation_reviews
          raise NotImplementedError, "#{self.class} must implement #annotation_reviews"
        end

        # @param section_ids [Array<String>]
        # @return [Hash{String => Hash}] section id => `{collection:, document_key:, source_path:, label:}`
        def locate(section_ids)
          raise NotImplementedError, "#{self.class} must implement #locate"
        end
      end
    end
  end
end
