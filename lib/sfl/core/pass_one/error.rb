# frozen_string_literal: true

module SFL
  module Core
    module PassOne
      # Raised when Pass 1 (syntactic parsing) fails for reasons other than
      # the sidecar transport itself (see SidecarError for that case).
      class Error < SFL::Error; end
    end
  end
end
