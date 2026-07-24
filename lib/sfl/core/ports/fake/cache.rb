# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Fake
        # In-memory Cache. `partition` returns hit values directly from the
        # same read that identifies them as hits — the behavior the Cache
        # port contract requires and the legacy double-read cache violated.
        class Cache
          include Ports::Cache

          def initialize
            @store = {}
          end

          def partition(keys)
            hits = {}
            misses = []
            keys.each do |key|
              if @store.key?(key)
                hits[key] = @store[key]
              else
                misses << key
              end
            end
            [hits, misses]
          end

          def write(key, value)
            @store[key] = value
            nil
          end
        end
      end
    end
  end
end
