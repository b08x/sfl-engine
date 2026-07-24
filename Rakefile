# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

task default: %i[spec rubocop]

namespace :db do
  desc "Run pending Sequel migrations against DATABASE_URL (db/migrations)"
  task :migrate do
    require "sequel"
    Sequel.extension :migration
    require_relative "lib/sfl"

    db = SFL::Store::Database.connect
    SFL::Store::Database.setup_extensions(db)
    Sequel::Migrator.run(db, "db/migrations")
    db.disconnect
  end
end
