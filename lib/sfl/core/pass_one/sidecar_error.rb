# frozen_string_literal: true

module SFL
  module Core
    module PassOne
      # Raised when the spaCy sidecar subprocess fails to start, exits
      # unexpectedly, or returns a malformed/error response.
      class SidecarError < Error; end
    end
  end
end
