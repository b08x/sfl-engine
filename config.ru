# frozen_string_literal: true

require_relative "boot"

# rack-livereload/guard-livereload aren't in the Gemfile — dev-only
# livereload is not wired up.

use Rack::Static, urls: ["/public"]
run Sfl
