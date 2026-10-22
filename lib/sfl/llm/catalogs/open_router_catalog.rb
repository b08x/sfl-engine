# frozen_string_literal: true

require "json"

module SFL
  module LLM
    module Catalogs
      # OpenRouter's model listing, /api/v1/models. Capabilities come from
      # each model's architecture modalities.
      class OpenRouterCatalog
        include Core::Ports::ModelCatalog

        PROVIDER = "openrouter"
        URL = "https://openrouter.ai/api/v1/models"

        # @param api_key [String, nil] sent as a bearer token when given
        # @param http [#call] (url, headers) -> body String
        # @param url [String]
        def initialize(api_key: nil, http: HttpGet.new, url: URL)
          @api_key = api_key
          @http = http
          @url = url
        end

        def name = PROVIDER

        def providers(_entries) = [PROVIDER]

        def fetch
          headers = @api_key ? { "Authorization" => "Bearer #{@api_key}" } : {}
          JSON.parse(@http.call(@url, headers)).fetch("data").map { |model| entry(model) }
        end

        private def entry(model)
          Core::Ports::ModelCatalog::Entry.new(provider: PROVIDER, model_id: model.fetch("id"), name: model["name"],
            context_window: model["context_length"], capabilities: capabilities(model.fetch("architecture", {})),
            pricing: model.fetch("pricing", {}))
        end

        private def capabilities(architecture)
          input = architecture.fetch("input_modalities", [])
          output = architecture.fetch("output_modalities", ["text"])
          capabilities = []
          capabilities << "chat" if output.include?("text")
          capabilities << "vision" if input.include?("image")
          capabilities << "embedding" if output.include?("embeddings")
          capabilities
        end
      end
    end
  end
end
