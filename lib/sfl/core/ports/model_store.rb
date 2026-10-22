# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # The `models` table (listed provider models) and the `task_models`
      # table (one assignment per task). Store::PgModelRepository is the
      # Postgres adapter.
      module ModelStore
        # Upserts +entries+ as available and marks every other model of
        # +providers+ unavailable. Deletes nothing.
        # @param entries [Array<ModelCatalog::Entry>]
        # @param providers [Array<String>]
        # @return [Hash] `{upserted:, unavailable:}`
        def sync(entries, providers:)
          raise NotImplementedError, "#{self.class} must implement #sync"
        end

        # @return [Array<Hash>] rows with provider, model_id, name, context_window,
        #   capabilities, pricing, available, fetched_at; ordered by provider and model id
        def list
          raise NotImplementedError, "#{self.class} must implement #list"
        end

        # @return [Hash{Symbol => Hash}] task => `{provider:, model_id:}`
        def assignments
          raise NotImplementedError, "#{self.class} must implement #assignments"
        end

        # Saves the one assignment for +task+, replacing any earlier one.
        # @param task [Symbol, String]
        # @return [void]
        def assign(task, provider:, model_id:)
          raise NotImplementedError, "#{self.class} must implement #assign"
        end
      end
    end
  end
end
