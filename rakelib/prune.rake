# frozen_string_literal: true

namespace :db do
  desc "Delete documents whose source file is gone, unless archived; pass dry-run to change nothing: " \
    "rake db:prune_missing_sources[dry-run]"
  task :prune_missing_sources, [:mode] do |_task, args|
    require_relative "../lib/sfl"

    mode = args[:mode].to_s
    abort "usage: rake db:prune_missing_sources[dry-run]" unless mode.empty? || mode == "dry-run"

    ctx = SFL::Boot.call(require_llm: false, require_tracing: false)
    logger = SFL::Boot.logger(load_dotenv: false)
    counts = SFL::Store::PruneMissingSources.new(ctx.db, logger:).call(dry_run: mode == "dry-run")
    puts "prune deleted=#{counts[:deleted]} kept_archived=#{counts[:kept_archived]} " \
      "kept_unreadable=#{counts[:kept_unreadable]}"
    ctx.db.disconnect
  rescue SFL::Store::Error => e
    abort "[ERROR] #{e.message}"
  end
end
