# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Scalar filters for Ports::Retriever#retrieve. Every attribute is
      # optional and defaults to nil ("no filter applied"), so
      # `RetrievalFilters.new` alone is a valid, filter-free query — callers
      # aren't forced to pass an empty Hash the way legacy's `filters: {}`
      # kwarg required.
      #
      # Deliberately a typed Dry::Struct rather than legacy's raw filters
      # Hash (F-track requirement, see the retrieval slice's card): a
      # typo'd key like `:mod` instead of `:mood` raises
      # Dry::Struct::Error::UnknownKeywordError at construction time
      # instead of legacy's `apply_filters` silently ignoring it (a
      # Hash#[] lookup on FIND_ALL_FILTERS that just returns nil for an
      # unrecognized key and skips filtering). Reusing the already-defined
      # MoodType/ProcessType/ModalityWeight/TenorValue enums/constraints
      # means an invalid value (bad enum member, out-of-range float) is
      # also rejected here, not silently matched against nothing downstream.
      class RetrievalFilters < Dry::Struct
        # Unknown-key input must raise, not silently no-op (F-track
        # requirement) — plain Dry::Struct ignores extra keys by default
        # (live-verified before writing this), so `schema.strict` is
        # required here, not decorative.
        schema schema.strict

        attribute :mood, Types::MoodType.optional.default(nil)
        attribute :min_modality, Types::ModalityWeight.optional.default(nil)
        attribute :max_modality, Types::ModalityWeight.optional.default(nil)
        attribute :min_tenor, Types::TenorValue.optional.default(nil)
        attribute :max_tenor, Types::TenorValue.optional.default(nil)
        attribute :process_type, Types::ProcessType.optional.default(nil)
        # source_type is a free-form provenance tag (see
        # db/migrations/005_add_source_type_to_clauses.rb) — legacy never
        # constrained it to an enum ("chat_native", "vault_markdown", "api",
        # ... grow without a fixed set), so it stays a plain optional String
        # rather than gaining an enum this slice would have to invent.
        attribute :source_type, Types::String.optional.default(nil)
      end
    end
  end
end
