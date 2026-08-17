# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module SFL
  module LLM
    # Native Net::HTTP-backed Core::Ports::Embedder adapter for Ollama.
    # Replaces the RubyLLM embedder, calling the local Ollama /api/embeddings
    # endpoint directly to eliminate gem bloat and dependency issues.
    #
    # 1. The `circuit_breaker` gem is dropped in favor of this codebase's
    #    own Core::Ports::Breaker port, injected as `breaker:`.
    #
    # 2. A failed embed call RAISES (SFL::LLM::Error) instead of silently
    #    returning nil/empty arrays.
    #
    # Configuration is fully injected (`model:`, `ollama_base_url:`) per
    # track decision 4 — this class never reads ENV itself.
    class Embedder
      include Core::Ports::Embedder

      # @param model [String] e.g. "embeddinggemma:latest"
      # @param ollama_base_url [String] e.g. "http://localhost:11434"
      # @param provider [Symbol] ignored, always assumed local/ollama
      # @param breaker [#call] Core::Ports::Breaker-compatible
      # @param logger [#debug,#info,#warn,#error] Core::Ports::Logger-compatible
      def initialize(
        model:,
        ollama_base_url:,
        provider: :ollama,
        breaker: Core::Ports::Null::Breaker.new,
        logger: Core::Ports::Null::Logger.new
      )
        @model = model
        @provider = provider
        @breaker = breaker
        @logger = logger
        @base_uri = URI(ollama_base_url.chomp("/"))
      end

      # @param text [String]
      # @return [Array<Float>]
      # @raise [ArgumentError] if text is nil/blank
      # @raise [SFL::LLM::Error] if the embedding call fails
      def embed(text)
        raise ArgumentError, "text must not be nil/blank" if text.nil? || text.strip.empty?

        breaker.call("embedder.embed") { fetch(text) }
      rescue ArgumentError
        raise
      rescue => e
        fail_embed("embed", e)
      end

      # @param texts [Array<String>]
      # @return [Array<Array<Float>>] one vector per input text, same order
      # @raise [SFL::LLM::Error] if the embedding call fails
      def embed_batch(texts)
        return [] if texts.empty?

        # Ollama /api/embeddings supports an array of strings in its `prompt` param (or `prompt` string)
        # depending on version, but typically `prompt` for single, `prompt` array or repeated /api/embeddings.
        # Actually /api/embed (new endpoint) supports `input: []`. We will use /api/embed which takes `input`.
        breaker.call("embedder.embed_batch") { fetch_batch(texts) }
      rescue => e
        fail_embed("embed_batch", e)
      end

      attr_reader :model, :provider, :breaker, :logger, :base_uri
      private :model, :provider, :breaker, :logger, :base_uri

      private def fetch(text)
        response = post_json("/api/embed", { model:, input: text })
        # /api/embed returns { "embeddings": [[...]] }
        embeddings = response.fetch("embeddings")
        embeddings.first
      end

      private def fetch_batch(texts)
        response = post_json("/api/embed", { model:, input: texts })
        response.fetch("embeddings")
      end

      private def post_json(path, payload)
        uri = URI.join(base_uri.to_s, path)
        request = Net::HTTP::Post.new(uri)
        request.content_type = "application/json"
        request.body = JSON.generate(payload)

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.request(request)
        end

        raise Error, "HTTP #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise Error, "Invalid JSON response: #{e.message}"
      end

      private def fail_embed(context, error)
        logger.error { "embedder #{context} failed: #{error.class}: #{error.message}" }
        raise Error, "embedder #{context} failed: #{error.message}"
      end
    end
  end
end
