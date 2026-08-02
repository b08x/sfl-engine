# frozen_string_literal: true

require "sequel"

module SFL
  module Store
    # Test-only connection helper for spec/store/*_spec.rb. Deliberately
    # NOT wired into a global RSpec.configure `before(:suite)` hook here —
    # this file lives under spec/support and is auto-required by
    # spec_helper.rb for every run of the suite, so registering a
    # postgres-connecting hook here would force every unrelated spec run
    # (loaders, pass_one, llm, ...) to need a live database. Store specs
    # opt in explicitly by calling `StoreTestDb.db` themselves.
    #
    # Points at a DEDICATED `sfl_engine_v2_test` database, not the
    # DATABASE_URL value in .env (`sfl_engine_dev`) — kept separate so this
    # file's own per-example TRUNCATE (#clean!, below) never wipes real
    # data from an interactive/manual run against the same Postgres
    # instance. docker-compose.yml's postgres service auto-creates this
    # database on first init (docker/init-test-db.sql); originally this
    # pointed at a bare `postgresql:///sfl_compiler_v2_dev` socket
    # connection to the host's system Postgres — moved onto the
    # docker-compose-managed instance 2026-08-02 alongside the app's own
    # DATABASE_URL, both for consistency and because the local Postgres's
    # `sfl_compiler_dev` database (note: no "v2") had ~7800 rows of the
    # legacy sfl-compiler repo's own dev data under a different,
    # incompatible schema, which running v2's migrations against risked
    # colliding with or destroying — irrelevant now that this points at
    # its own fresh, dedicated database instead.
    module StoreTestDb
      TEST_DATABASE_URL = ENV.fetch("DATABASE_URL_V2_TEST", "postgresql://sfl:sfl@localhost:5433/sfl_engine_v2_test")

      def self.db
        @db ||= begin # rubocop:disable ThreadSafety/ClassInstanceVariable -- test-only memoized
          # connection, single-threaded RSpec run, mirrors lib/sfl.rb's own @loader pattern.
          database = Database.connect(TEST_DATABASE_URL)
          Database.setup_extensions(database)
          Sequel.extension :migration
          Sequel::Migrator.run(database, "db/migrations")
          database
        end
      end

      # Truncate every store table, restarting identity sequences, so each
      # example starts from a clean slate — CASCADE clears
      # ideational/interpersonal/embeddings rows too, but TRUNCATE lists
      # every table explicitly for clarity rather than relying on cascade.
      def self.clean!
        db.run(<<~SQL)
          TRUNCATE clauses, ideational_payloads, interpersonal_payloads, embeddings,
                   annotation_reviews, review_queue
          RESTART IDENTITY CASCADE
        SQL
      end
    end
  end
end
