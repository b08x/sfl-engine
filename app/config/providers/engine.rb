# frozen_string_literal: true

module Providers
  # Single composition point Roda routes pull collaborators from. Wraps
  # SFL::API::Context.build (lib/sfl/api/context.rb) so the CLI and the
  # Roda app share one wiring path instead of two.
  class Engine
    def self.boot(sfl_boot_result)
      @ctx = SFL::API::Context.build(sfl_boot_result)
      @debug_errors = sfl_boot_result.api_debug_errors
      @cors_origins = sfl_boot_result.api_cors_origins
    end

    def self.get = @ctx
    def self.debug_errors? = @debug_errors
    def self.cors_origins = @cors_origins || []
  end
end
