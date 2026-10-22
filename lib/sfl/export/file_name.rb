# frozen_string_literal: true

module SFL
  module Export
    # Export file names: `<collection>-<timestamp>.<extension>`.
    module FileName
      extend self

      TIMESTAMP = "%Y%m%dT%H%M%S"
      UNSAFE = /[^A-Za-z0-9._-]+/

      # @param collection [String]
      # @param time [Time]
      # @param extension [String]
      # @return [String]
      def call(collection, time, extension)
        "#{collection.to_s.gsub(UNSAFE, '_')}-#{time.strftime(TIMESTAMP)}.#{extension}"
      end
    end
  end
end
