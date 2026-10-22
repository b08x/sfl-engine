# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # Empty BrowseSource: no collections, no reviews.
        class BrowseSource
          include Ports::BrowseSource

          def collections = []
          def documents(_collection_id) = []
          def sections(_document_id) = []
          def clauses(_section_id) = []
          def content_reviews = []
          def annotation_reviews = {}
          def locate(_section_ids) = {}
        end
      end
    end
  end
end
