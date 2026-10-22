# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # No-op SectionRegistry: runs the block and records nothing.
        class SectionRegistry
          include Ports::SectionRegistry

          def transaction = yield

          def register(_unit, _clause_count)
            nil
          end
        end
      end
    end
  end
end
