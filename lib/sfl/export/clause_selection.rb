# frozen_string_literal: true

module SFL
  module Export
    # Resolves chosen sections to the clauses to export: each clause once,
    # ordered by document and then section ordinal, clauses in stored order.
    class ClauseSelection
      # @param source [Core::Ports::BrowseSource]
      def initialize(source:)
        @source = source
      end

      # @param picks [Array<SectionPick>]
      # @return [Array<ClauseRecord>]
      def resolve(picks)
        seen = {}
        picks.sort_by(&:order).flat_map do |pick|
          chosen(pick).filter_map do |clause|
            next if seen.key?(clause[:id])

            seen[clause[:id]] = true
            ClauseRecord.new(
              pick:, id: clause[:id], text: clause[:text],
              ideational: clause.fetch(:ideational, {}), interpersonal: clause.fetch(:interpersonal, {})
            )
          end
        end
      end

      private def chosen(pick)
        clauses = @source.clauses(pick.section_id)
        pick.clause_ids ? clauses.select { |clause| pick.clause_ids.include?(clause[:id]) } : clauses
      end
    end
  end
end
