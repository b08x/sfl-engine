# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Provenance status for a normalized Pass 2 classification.
      ClassificationStatus = String.enum("exact", "aliased", "fuzzy", "unknown")
    end
  end
end
