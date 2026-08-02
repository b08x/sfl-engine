# frozen_string_literal: true

# Rack entry point for `bundle exec falcon serve` / `bundle exec sfl-api`.
# Running from a repo checkout (no gemspec — track decision 1), same as
# exe/sfl-analyze.

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require_relative "lib/sfl"

SFL::DockerServices.ensure_running!

boot_result = SFL::Boot.call(require_llm: true, require_tracing: true)
ctx = SFL::API.build_context(boot_result)

run SFL::API::Server.new(ctx, debug_errors: boot_result.api_debug_errors, cors_origins: boot_result.api_cors_origins)
