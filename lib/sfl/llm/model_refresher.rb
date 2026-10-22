# frozen_string_literal: true

module SFL
  module LLM
    # Reads every model catalog and syncs its entries into the ModelStore.
    # A catalog that fails is logged and skipped: its provider's rows are
    # neither updated nor flagged, and the other catalogs still sync.
    class ModelRefresher
      # One catalog's outcome. `error` is nil on success.
      Outcome = Data.define(:catalog, :upserted, :unavailable, :error) do
        def to_s = error ? "#{catalog}: failed (#{error})" : "#{catalog}: #{upserted} listed, #{unavailable} unavailable"
      end

      # @param catalogs [Array<Core::Ports::ModelCatalog>]
      # @param store [Core::Ports::ModelStore]
      # @param logger [Core::Ports::Logger]
      def initialize(catalogs:, store:, logger:)
        @catalogs = catalogs
        @store = store
        @logger = logger
      end

      # @return [Array<Outcome>] one per catalog, in order
      def call = @catalogs.map { |catalog| refresh(catalog) }

      private def refresh(catalog)
        entries = catalog.fetch
        counts = @store.sync(entries, providers: catalog.providers(entries))
        @logger.info("models refreshed", catalog: catalog.name, **counts)
        Outcome.new(catalog: catalog.name, error: nil, **counts)
      rescue => e
        detail = "#{e.class}: #{e.message}"
        @logger.error("model refresh failed", catalog: catalog.name, error: detail)
        Outcome.new(catalog: catalog.name, upserted: 0, unavailable: 0, error: detail)
      end
    end
  end
end
