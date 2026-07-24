# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # No-op Retriever: returns no results for any query.
        class Retriever
          include Ports::Retriever

          def retrieve(_query)
            []
          end
        end
      end
    end
  end
end
