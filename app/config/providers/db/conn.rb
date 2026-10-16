# frozen_string_literal: true

module Providers
  module DB
    class Conn
      def self.boot
        @conn = SFL::Store::Database.connect(Config.get[:db][:url])
        SFL::Store::Database.setup_extensions(@conn)

        Sequel::Model.plugin :timestamps, update_on_create: true
      end

      def self.get = @conn
    end
  end
end
