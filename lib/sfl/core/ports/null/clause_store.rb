# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # No-op ClauseStore: discards writes, returns no clauses on read.
        class ClauseStore
          include Ports::ClauseStore

          def replace_document(_document_id, _clauses)
            nil
          end

          def find_by_document(_document_id)
            []
          end
        end
      end
    end
  end
end
