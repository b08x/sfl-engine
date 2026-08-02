-- Runs automatically on first container init (docker-entrypoint-initdb.d).
-- A separate, dedicated database for spec/support/store_test_db.rb — kept
-- apart from the app's own POSTGRES_DB (sfl_engine_dev) so the test
-- suite's per-example TRUNCATE never touches real data from an
-- interactive/manual run against the same container.
CREATE DATABASE sfl_engine_v2_test;
