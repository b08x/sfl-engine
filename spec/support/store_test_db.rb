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
    # Points at a DEDICATED `sfl_compiler_v2_dev` database, not the
    # DATABASE_URL value in .env (`sfl_compiler_dev`) — that database
    # already holds ~7800 rows of the legacy sfl-compiler repo's own
    # dev data under a different, incompatible clauses/ideational_payloads/
    # interpersonal_payloads/embeddings schema (no FKs, extra topic_id/
    # source_type columns, etc.), verified live with `psql -d
    # sfl_compiler_dev -c "\dt"` and row counts before writing this.
    # Running v2's versioned migrations against it would either collide
    # (table already exists) or, if forced, destroy that data. See the
    # slice report for the human-review action this implies for .env.
    module StoreTestDb
      TEST_DATABASE_URL = ENV.fetch("DATABASE_URL_V2_TEST", "postgresql:///sfl_compiler_v2_dev")

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
        db.run("TRUNCATE clauses, ideational_payloads, interpersonal_payloads, embeddings RESTART IDENTITY CASCADE")
      end
    end
  end
end
