# frozen_string_literal: true

require "dry-types"
require "dry-struct"
require "securerandom"

module SFL
  module Core
    # Namespace for dry-types scalar/enum aliases and dry-struct value
    # objects used across Pass 1/Pass 2. Each constant lives in its own
    # file under types/ (Zeitwerk: one constant per file) — this file
    # only sets up the shared Dry.Types() include that the rest of the
    # namespace's files rely on via `Types::Float`, `Types::String`, etc.
    module Types
      include Dry.Types()
    end
  end
end
