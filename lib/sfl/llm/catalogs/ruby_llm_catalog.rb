# frozen_string_literal: true

module SFL
  module LLM
    module Catalogs
      # The ruby_llm model registry after `RubyLLM.models.refresh`. Ollama
      # and OpenRouter models are left out: OllamaCatalog and
      # OpenRouterCatalog list those providers from their own endpoints.
      class RubyLLMCatalog
        include Core::Ports::ModelCatalog

        EXCLUDED_PROVIDERS = [OllamaCatalog::PROVIDER, OpenRouterCatalog::PROVIDER].freeze

        # Refreshes the process-wide registry (remote providers only) and
        # returns its RubyLLM::Model entries (ruby_llm 2.x).
        REFRESH = lambda do
          require "ruby_llm"
          RubyLLM::Models.refresh(remote_only: true)
          RubyLLM.models.all
        end

        # @param registry [#call] -> Array<RubyLLM::Model>
        def initialize(registry: REFRESH)
          @registry = registry
        end

        def name = "ruby_llm"

        def providers(entries) = entries.map(&:provider).uniq

        def fetch
          @registry.call.reject { |info| EXCLUDED_PROVIDERS.include?(info.provider.to_s) }.map { |info| entry(info) }
        end

        private def entry(info)
          Core::Ports::ModelCatalog::Entry.new(provider: info.provider.to_s, model_id: info.id, name: info.name,
            context_window: info.context_window, capabilities: capabilities(info), pricing: info.pricing.to_h)
        end

        private def capabilities(info)
          type = info.type.to_s
          base = (type == "embedding") ? ["embedding"] : []
          base << "chat" if type == "chat"
          base << "vision" if info.modalities.input.include?("image")
          (base + info.capabilities.map(&:to_s)).uniq
        end
      end
    end
  end
end
