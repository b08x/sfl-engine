# frozen_string_literal: true

require "json"

module SFL
  module LLM
    module Catalogs
      # The models an Ollama server has pulled, from its /api/tags listing.
      # The listing names no capabilities, so they are read from the model
      # name: embedding models name "embed", vision models a vision family.
      class OllamaCatalog
        include Core::Ports::ModelCatalog

        PROVIDER = "ollama"
        EMBEDDING = /embed/i
        VISION = /llava|vision|-vl\b|vl:|moondream|bakllava/i

        # @param base_url [String] e.g. "http://localhost:11434"
        # @param http [#call] (url, headers) -> body String
        def initialize(base_url:, http: HttpGet.new)
          @base_url = base_url.chomp("/")
          @http = http
        end

        def name = PROVIDER

        def providers(_entries) = [PROVIDER]

        def fetch
          JSON.parse(@http.call("#{@base_url}/api/tags", {})).fetch("models").map { |model| entry(model) }
        end

        private def entry(model)
          id = model.fetch("name")
          Core::Ports::ModelCatalog::Entry.new(provider: PROVIDER, model_id: id, name: id, context_window: nil,
            capabilities: capabilities(id), pricing: {})
        end

        private def capabilities(id)
          return ["embedding"] if id.match?(EMBEDDING)

          id.match?(VISION) ? %w[chat vision] : ["chat"]
        end
      end
    end
  end
end
