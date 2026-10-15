# frozen_string_literal: true

module Providers
  module Mailer
    def self.boot
      ::Mail.defaults do
        delivery_method :logger if Config.not_production?
      end
    end
  end
end
