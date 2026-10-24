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

  desc "Archive a document by exact document_key (excluded from default retrieval, kept by prune): " \
    "rake db:archive_document[KEY]"
  task :archive_document, [:key] do |_task, args|
    require_relative "../lib/sfl"

    key = args[:key].to_s
    abort "usage: rake db:archive_document[KEY]" if key.strip.empty?

    ctx = SFL::Boot.call(require_llm: false, require_tracing: false)
    outcome = SFL::Store::DocumentArchive.new(ctx.db).archive(key)
    if outcome == :already_archived
      puts "document #{key} is already archived; archived_at is unchanged"
    else
      puts "archived document #{key}"
    end
    ctx.db.disconnect
  rescue SFL::Store::Error => e
    abort "[ERROR] #{e.message}"
  end

  desc "Unarchive a document by exact document_key: rake db:unarchive_document[KEY]"
  task :unarchive_document, [:key] do |_task, args|
    require_relative "../lib/sfl"

    key = args[:key].to_s
    abort "usage: rake db:unarchive_document[KEY]" if key.strip.empty?

    ctx = SFL::Boot.call(require_llm: false, require_tracing: false)
    outcome = SFL::Store::DocumentArchive.new(ctx.db).unarchive(key)
    if outcome == :not_archived
      puts "document #{key} is not archived; nothing changed"
    else
      puts "unarchived document #{key}"
    end
    ctx.db.disconnect
  rescue SFL::Store::Error => e
    abort "[ERROR] #{e.message}"
  end
end
