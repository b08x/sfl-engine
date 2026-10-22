# frozen_string_literal: true

module SFL
  module TUI
    module Browse
      # Review state per section (content review) and per clause
      # (annotation review), reduced to the status filter's vocabulary:
      # "pending", "accepted" or "rejected".
      class Reviews
        CONTENT_STATUS = {
          "pending" => "pending",
          "approved" => "accepted",
          "edited" => "accepted",
          "rejected" => "rejected",
        }.freeze

        # @param content [Array<Hash>] BrowseSource#content_reviews rows, oldest first
        # @param annotations [Hash{String => Hash}] BrowseSource#annotation_reviews
        def initialize(content: [], annotations: {})
          @by_section = content.group_by { |row| row[:section_id] }
          @annotations = annotations
          freeze
        end

        # @return [Hash, nil] the section's pending content-review item, or its latest decided one
        def item(section_id)
          rows = @by_section.fetch(section_id, [])
          rows.find { |row| row[:status] == "pending" } || rows.last
        end

        # @return [Boolean] whether the section has a pending content-review item
        def pending?(section_id) = item(section_id)&.dig(:status) == "pending"

        # @return [String, nil]
        def section_status(section_id) = CONTENT_STATUS[item(section_id)&.dig(:status)]

        # @return [Hash, nil] `{status:, confidence:}`
        def annotation(clause_id) = @annotations[clause_id]

        # @return [Boolean] whether the clause is in the annotation review queue undecided
        def annotation_pending?(clause_id) = annotation(clause_id)&.dig(:status) == "pending"

        # @return [String, nil] the clause's annotation status, else its section's content status
        def clause_status(clause_id, section_id) = annotation(clause_id)&.dig(:status) || section_status(section_id)
      end
    end
  end
end
