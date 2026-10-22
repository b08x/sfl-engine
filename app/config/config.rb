# frozen_string_literal: true

# Settings for the Roda app. Values come from SFL::Boot, the only code that
# reads ENV (see SFL::Boot.web_settings and SFL::Boot.rack_environment).
module Config
  class << self
    def get = @config ||= SFL::Boot.web_settings

    def not_production? = environment != "production"

    def environment = SFL::Boot.rack_environment
  end
end
