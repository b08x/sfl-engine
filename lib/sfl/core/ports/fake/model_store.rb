# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Fake
        # In-memory ModelStore with the same sync rule as the Postgres one.
        class ModelStore
          include Ports::ModelStore

          # @param models [Array<Hash>] initial model rows
          # @param assignments [Hash{Symbol => Hash}] initial task assignments
          # @param clock [#call] returns the current Time
          def initialize(models: [], assignments: {}, clock: -> { Time.now })
            @models = models.to_h { |row| [[row[:provider], row[:model_id]], row] }
            @assignments = assignments.dup
            @clock = clock
          end

          def sync(entries, providers:)
            now = @clock.call
            entries.each { |entry| @models[[entry.provider, entry.model_id]] = entry.to_row.merge(available: true, fetched_at: now) }
            listed = entries.to_set { |entry| [entry.provider, entry.model_id] }
            missing = @models.reject { |key, row| listed.include?(key) || !providers.include?(row[:provider]) }
            missing.each_value { |row| row[:available] = false }
            { upserted: entries.size, unavailable: missing.size }
          end

          def list = @models.values.sort_by { |row| [row[:provider], row[:model_id]] }

          def assignments = @assignments.dup

          def assign(task, provider:, model_id:)
            @assignments[task.to_sym] = { provider:, model_id: }
            nil
          end
        end
      end
    end
  end
end
