# frozen_string_literal: true

require "net/http"
require "uri"

module SFL
  module LLM
    module Catalogs
      # The default HTTP seam for the Ollama and OpenRouter catalogs: one
      # GET, returning the body of a 2xx reply. Specs pass a lambda instead.
      class HttpGet
        # @param timeout [Numeric] open and read timeout in seconds
        def initialize(timeout: 10)
          @timeout = timeout
        end

        # @param url [String]
        # @param headers [Hash{String => String}]
        # @return [String] the response body
        # @raise [LLM::Error] on a non-2xx reply
        def call(url, headers = {})
          uri = URI(url)
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
            open_timeout: @timeout, read_timeout: @timeout) { |http| http.get(uri.request_uri, headers) }
          raise Error, "GET #{url} returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

          response.body
        end
      end
    end
  end
end
