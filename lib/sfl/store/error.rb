# frozen_string_literal: true

module SFL
  module Store
    # Raised for storage-layer misconfiguration that Postgres itself would
    # otherwise report as a cryptic driver-level exception (e.g. pgvector's
    # bare "expected N dimensions, not M").
    class Error < SFL::Error; end
  end
end
