# frozen_string_literal: true

namespace :models do
  desc "Fill the models table from the ruby_llm registry and the Ollama and OpenRouter listings; " \
    "models missing from a listing are marked unavailable, never deleted"
  task :refresh do
    require_relative "../lib/sfl"

    ctx = SFL::Boot.call(require_llm: false, require_tracing: false)
    store = SFL::Store::PgModelRepository.new(ctx.db)
    refresher = SFL::LLM::ModelRefresher.new(catalogs: SFL::Boot.model_catalogs(load_dotenv: false), store:,
      logger: SFL::Boot.logger(load_dotenv: false))
    outcomes = refresher.call
    outcomes.each { |outcome| puts outcome }
    failed = outcomes.select(&:error)
    abort "[ERROR] #{failed.size} of #{outcomes.size} catalogs failed" unless failed.empty?
  rescue SFL::Boot::Error => e
    abort "[ERROR] #{e.message}"
  end
end
