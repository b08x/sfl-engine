# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # A ModelStore that keeps nothing: no models, no assignments.
        class ModelStore
          include Ports::ModelStore

          def sync(entries, providers:) = { upserted: 0, unavailable: 0 } # rubocop:disable Lint/UnusedMethodArgument -- port contract
          def list = []
          def assignments = {}
          def assign(_task, provider:, model_id:) = nil # rubocop:disable Lint/UnusedMethodArgument -- port contract
        end
      end
    end
  end
end
