# frozen_string_literal: true

require "sequel"

module SFL
  module Store
    # Scalar filter => how to apply it against a query already joined
    # against clauses/ideational_payloads/interpersonal_payloads. Same
    # lambda-table shape as legacy's ClauseRepository::FIND_ALL_FILTERS
    # (the retrieval slice's card explicitly says to reuse that pattern,
    # not reinvent it) — one 1-arity proc per filter, table-qualified so it
    # composes safely once multiple joined tables are in the same query.
    #
    # Standalone (not nested under PgHybridRetriever) so a later
    # Corpus-Browser-style filtered-listing feature can `where(build.call(v))`
    # against the same lambda table without duplicating it — mirrors why
    # legacy's own FIND_ALL_FILTERS lived on ClauseRepository rather than
    # inside HybridRetriever, just split into its own file here since v2
    # has no single "repository" class both features would otherwise share.
    module ClauseFilters
      FIND_ALL_FILTERS = {
        mood: -> (v) { { Sequel[:interpersonal_payloads][:mood] => v } },
        min_modality: -> (v) { Sequel[:interpersonal_payloads][:modality_weight] >= v },
        max_modality: -> (v) { Sequel[:interpersonal_payloads][:modality_weight] <= v },
        min_tenor: -> (v) { Sequel[:interpersonal_payloads][:tenor] >= v },
        max_tenor: -> (v) { Sequel[:interpersonal_payloads][:tenor] <= v },
        process_type: -> (v) { { Sequel[:ideational_payloads][:process_type] => v } },
        source_type: -> (v) { { Sequel[:clauses][:source_type] => v } },
      }.freeze

      # @param dataset [Sequel::Dataset] already joined against every table
      #   FIND_ALL_FILTERS references
      # @param filters [SFL::Core::Types::RetrievalFilters]
      # @return [Sequel::Dataset] the same dataset with one #where per
      #   non-nil filter attribute applied
      def self.apply(dataset, filters)
        filters.to_h.compact.reduce(dataset) do |scope, (key, value)|
          scope.where(FIND_ALL_FILTERS.fetch(key).call(value))
        end
      end
    end
  end
end
