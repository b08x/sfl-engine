# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # A source of provider model listings: the ruby_llm registry, Ollama's
      # /api/tags, OpenRouter's /api/v1/models. LLM::ModelRefresher reads each
      # catalog and hands the entries to a ModelStore.
      module ModelCatalog
        # Capability names a task can need (Boot::TaskModelResolver::CAPABILITIES).
        CAPABILITIES = %w[chat embedding vision].freeze

        # One listed model.
        # - `capabilities`: Array<String>, a subset of CAPABILITIES plus any provider flags
        # - `pricing`: Hash, provider-shaped prices, empty when unknown
        Entry = Data.define(:provider, :model_id, :name, :context_window, :capabilities, :pricing) do
          def to_row = to_h
        end

        # @return [String] the catalog's name, for logs and refresh summaries
        def name
          raise NotImplementedError, "#{self.class} must implement #name"
        end

        # @return [Array<String>] the providers this catalog is authoritative
        #   for: a model of one of these providers missing from #fetch is
        #   marked unavailable
        def providers(_entries)
          raise NotImplementedError, "#{self.class} must implement #providers"
        end

        # @return [Array<Entry>]
        # @raise [StandardError] when the listing cannot be read
        def fetch
          raise NotImplementedError, "#{self.class} must implement #fetch"
        end
      end
    end
  end
end
