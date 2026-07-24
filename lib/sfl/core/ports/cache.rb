# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Caches Pass 2 annotation results keyed by a content hash, so
      # unchanged clauses skip a real LLM call on re-runs. `partition` is
      # its own method (not `keys.map { |k| [k, fetch(k)] }`) because the
      # legacy implementation read cache entries twice — once to partition
      # hits from misses, once more to fetch each hit's value — and that
      # double read is exactly the bug this port's contract forbids: a
      # conforming adapter must return hit values in the same call that
      # identifies them as hits.
      module Cache
        # @param keys [Array<String>]
        # @return [[Hash<String, Object>, Array<String>]] [hits, miss_keys]
        def partition(keys)
          raise NotImplementedError, "#{self.class} must implement #partition"
        end

        # @param key [String]
        # @param value [Object]
        # @return [void]
        def write(key, value)
          raise NotImplementedError, "#{self.class} must implement #write"
        end
      end
    end
  end
end
