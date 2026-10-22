# frozen_string_literal: true

module SFL
  module TUI
    module Browse
      # The Browse status filter: all, pending review, accepted, rejected.
      module StatusFilter
        extend self

        LABELS = { "all" => "all", "pending" => "pending review", "accepted" => "accepted", "rejected" => "rejected" }.freeze
        VALUES = LABELS.keys.freeze

        # @return [String] the filter after +filter+, wrapping around
        def next(filter) = VALUES[(VALUES.index(filter).to_i + 1) % VALUES.size]

        # @return [String]
        def label(filter) = LABELS.fetch(filter)

        # @param status [String, nil]
        def match?(filter, status) = filter == "all" || filter == status
      end
    end
  end
end
