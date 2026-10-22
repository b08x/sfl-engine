# frozen_string_literal: true

require "sequel"

module SFL
  module Store
    # Postgres ModelStore over the `models` (migration 018) and `task_models`
    # (019) tables. #sync upserts and flags; it never deletes a model row.
    class PgModelRepository
      include Core::Ports::ModelStore

      # @param db [Sequel::Database]
      # @param clock [#call] returns the current Time
      def initialize(db, clock: -> { Time.now })
        @db = db
        @clock = clock
      end

      def sync(entries, providers:)
        now = @clock.call
        @db.transaction do
          entries.each { |entry| upsert(entry, now) }
          { upserted: entries.size, unavailable: flag_missing(entries, providers) }
        end
      end

      def list
        models.order(:provider, :model_id).all.map do |row|
          row.except(:id).merge(capabilities: row[:capabilities].to_a, pricing: row[:pricing].to_h)
        end
      end

      def assignments
        @db[:task_models].all.to_h { |row| [row[:task].to_sym, { provider: row[:provider], model_id: row[:model_id] }] }
      end

      def assign(task, provider:, model_id:)
        row = { provider: provider.to_s, model_id:, updated_at: @clock.call }
        @db[:task_models].insert_conflict(target: :task, update: row).insert(row.merge(task: task.to_s))
        nil
      end

      private def models = @db[:models]

      private def upsert(entry, now)
        row = {
          name: entry.name,
          context_window: entry.context_window,
          capabilities: Sequel.pg_jsonb(entry.capabilities),
          pricing: Sequel.pg_jsonb(entry.pricing),
          available: true,
          fetched_at: now,
        }
        models.insert_conflict(target: %i[provider model_id], update: row)
          .insert(row.merge(provider: entry.provider, model_id: entry.model_id))
      end

      private def flag_missing(entries, providers)
        listed = entries.map { |entry| [entry.provider, entry.model_id] }
        scope = models.where(provider: providers, available: true)
        scope = scope.exclude(%i[provider model_id] => listed) unless listed.empty?
        scope.update(available: false)
      end
    end
  end
end
