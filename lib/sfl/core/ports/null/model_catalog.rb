# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # A catalog that lists nothing and claims no providers.
        class ModelCatalog
          include Ports::ModelCatalog

          def name = "null"
          def providers(_entries) = []
          def fetch = []
        end
      end
    end
  end
end
