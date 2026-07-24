# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Migration action enum for KnowledgeBaseSource's manifest (default
      # :review so a partial/interrupted build is always safe) — ported
      # from legacy Types::MigrationAction verbatim.
      MigrationAction = Coercible::Symbol.default(:review).enum(
        :keep, :update, :archive, :review, :merge_candidate
      )
    end
  end
end
