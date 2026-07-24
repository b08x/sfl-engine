# frozen_string_literal: true

module SFL
  module Core
    module Loaders
      # Raised for malformed/unsupported source files (fixes S2/S3-style
      # namespaced error handling — a Loaders-specific error, not a bare
      # RuntimeError, so callers can rescue loader failures specifically).
      class Error < SFL::Error; end
    end
  end
end
