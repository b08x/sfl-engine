# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # Always-miss Cache: every key partitions as a miss, writes are
        # discarded. Useful for forcing a full re-annotation in tests.
        class Cache
          include Ports::Cache

          def partition(keys)
            [{}, keys]
          end

          def write(_key, _value)
            nil
          end
        end
      end
    end
  end
end
