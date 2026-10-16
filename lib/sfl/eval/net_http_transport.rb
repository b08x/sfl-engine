# frozen_string_literal: true

require "net/http"

module SFL
  module Eval
    # Default LangfuseClient transport: one Net::HTTP request per call.
    class NetHttpTransport
      VERBS = {
        get: Net::HTTP::Get,
        post: Net::HTTP::Post,
        put: Net::HTTP::Put,
        patch: Net::HTTP::Patch,
        delete: Net::HTTP::Delete,
      }.freeze

      def initialize(read_timeout: 30)
        @read_timeout = read_timeout
      end

      def call(method, url, headers, body)
        uri = URI(url)
        request = VERBS.fetch(method).new(uri)
        headers.each { |key, value| request[key] = value }
        request.body = body if body
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = @read_timeout
        reply = http.request(request)
        LangfuseClient::Response.new(reply.code.to_i, reply.body)
      end
    end
  end
end
