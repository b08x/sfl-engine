# frozen_string_literal: true

namespace :db do
  desc "Delete a collection with its documents, sections and clauses, printing the counts: " \
    "rake db:purge_collection[NAME]"
  task :purge_collection, [:name] do |_task, args|
    require_relative "../lib/sfl"

    name = args[:name].to_s.strip
    abort "usage: rake db:purge_collection[NAME]" if name.empty?

    ctx = SFL::Boot.call(require_llm: false, require_tracing: false)
    counts = SFL::Store::CollectionPurger.new(ctx.db).purge(name)
    puts "purged collection=#{name} #{counts.map { |key, count| "#{key}=#{count}" }.join(' ')}"
  rescue SFL::Store::Error => e
    abort "[ERROR] #{e.message}"
  end
end
