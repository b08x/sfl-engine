# frozen_string_literal: true

require "sequel"

module SFL
  module Store
    # Database connection manager. Deliberately just connection setup —
    # running migrations is a separate, explicit step (`rake db:migrate`,
    # see Rakefile / lib/tasks/db.rake), never automatic at boot or per-job
    # (D5: legacy's Migrator ran ad hoc from bootstrap.rb with no
    # versioning; Store::Database has no `run_migrations` method at all).
    module Database
      # :pool_class => :timed_queue plus the fiber_concurrency extension are
      # both required for correctness under a fiber-based server (Falcon).
      # Falcon runs concurrent requests as Async fibers within a single
      # thread; Sequel's default pool checks out connections keyed on
      # Sequel.current, which defaults to Thread.current — so without
      # fiber_concurrency, #hold treats two sibling fibers on the same
      # thread as "the same caller" (its re-entrant-hold fast path) and
      # hands them the SAME pg connection, even with a fiber-capable pool
      # class selected. Two concurrent requests would then interleave
      # queries on one socket (legacy surfaced this as garbled
      # NoMethodErrors deep in the pg/Sequel adapter).
      #
      # Kept here even though this Phase 2 slice has no Falcon/API server
      # yet (no `falcon`/`async` gem in this Gemfile) — Store::Database is
      # the one place a future Phase 4 boot process will get its connection
      # from, and loading the extension now costs nothing (it only changes
      # how Sequel.current resolves; it's a no-op under a plain threaded or
      # single-fiber process). Better to have it in place before the bug
      # it prevents can recur than to re-derive this comment later.
      Sequel.extension :fiber_concurrency

      # @param url [String, nil] defaults to ENV["DATABASE_URL"]
      # @return [Sequel::Database]
      def self.connect(url = nil)
        url ||= ENV.fetch("DATABASE_URL")
        db = Sequel.connect(url, pool_class: :timed_queue)

        # Enable pg_json extension (supports jsonb via Sequel.pg_jsonb)
        db.extension :pg_json

        # Every `DateTime`/timestamp column in db/migrations is "timestamp
        # without time zone" — Postgres stores those as naive wall-clock
        # values with no zone info attached. Without pinning both sides to
        # :utc, Sequel's default (:local) reads a stored value back
        # tagged with the *server's* local offset instead of the offset
        # the Ruby Time was actually written in, silently shifting the
        # instant a round trip produces (live-verified: PgClauseStore's
        # own round-trip spec failed on `compiled_at` until this was
        # added). Setting both makes "the digits stored are always UTC
        # digits" hold in both directions.
        db.timezone = :utc
        Sequel.application_timezone = :utc

        db
      end

      # Idempotent: `CREATE EXTENSION IF NOT EXISTS` is safe to call every
      # time. Both extensions are already installed in the dev database
      # (verified via `psql -d sfl_compiler_dev -c "\dx"` before writing
      # this); this method exists for other environments (CI, a fresh
      # local Postgres) where they aren't yet.
      #
      # @param db [Sequel::Database]
      # @return [void]
      def self.setup_extensions(db)
        db.execute("CREATE EXTENSION IF NOT EXISTS vector")
        db.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
        nil
      end
    end
  end
end
